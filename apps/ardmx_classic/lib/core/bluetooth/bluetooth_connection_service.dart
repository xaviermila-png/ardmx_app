import 'dart:async';

import 'package:flutter/widgets.dart' show debugPrint;
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bluetooth_connection_state.dart';

/// A paired Classic (SPP) device — address + display name, nothing
/// plugin-specific.
class DiscoveredDevice {
  const DiscoveredDevice({required this.address, this.name});

  final String address;
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is DiscoveredDevice && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

/// Owns the single Bluetooth Classic (SPP) connection to the Mega/HC-06.
/// This app has no other transport — Bluetooth Classic isn't available on
/// iOS, which is why this app (unlike its BLE sibling "ARDMX") is Android
/// only.
///
/// Connecting and disconnecting are both fully explicit user actions: there
/// is no auto-connect on launch and no automatic reconnect on drop. This is
/// deliberate — found necessary while diagnosing a real HC-05 connectivity
/// issue, where auto-retry logic made failures harder to reproduce/diagnose
/// by hammering the module with rapid reconnect attempts.
class BluetoothConnectionService extends Notifier<BluetoothConnectionState> {
  static const _lastDeviceAddressKey = 'last_bluetooth_device_address';

  final FlutterBlueClassic _plugin = FlutterBlueClassic();
  final StreamController<List<int>> _incomingBytesController =
      StreamController<List<int>>.broadcast();

  BluetoothConnection? _connection;
  StreamSubscription<List<int>>? _inputSubscription;

  /// Broadcast stream of raw bytes received from the connected device.
  /// Outlives any individual connection — `VirtuinoProtocol` is built on
  /// top of this once and doesn't need to be recreated when the user
  /// disconnects and reconnects.
  Stream<List<int>> get incomingBytes => _incomingBytesController.stream;

  @override
  BluetoothConnectionState build() {
    // Leaving the app foreground (Home button, task switcher, Recents) does
    // NOT disconnect — only an explicit user action does (Splash's
    // "Sortir"/back-button). An earlier auto-disconnect-on-pause behavior
    // was removed at the user's request: they want the connection to
    // survive simply switching apps or checking notifications.
    ref.onDispose(() {
      _inputSubscription?.cancel();
      _connection?.dispose();
      _incomingBytesController.close();
    });
    return BluetoothConnectionState.initial;
  }

  Future<List<DiscoveredDevice>> pairedDevices() async {
    final devices = await _plugin.bondedDevices ?? const [];
    return [
      for (final device in devices)
        DiscoveredDevice(address: device.address, name: device.name),
    ];
  }

  /// Active discovery scan — only used by the Debug screen's "Refrescar nom"
  /// button, to nudge Android into re-reading a bonded device's current
  /// advertised name without forgetting/re-pairing it. Everywhere else in
  /// the app deliberately only ever talks to already-bonded devices and
  /// never scans; this is a narrow, opt-in exception to that rule, not a
  /// reversal of it. Not guaranteed to update Android's persisted
  /// paired-device name on every OS version/OEM — forgetting and re-pairing
  /// remains the reliable fallback.
  void startScan() => _plugin.startScan();

  void stopScan() => _plugin.stopScan();

  Stream<BluetoothDevice> get scanResults => _plugin.scanResults;

  /// The address of the last device a connection was ever successfully
  /// established with, purely to pre-select it in the device picker —
  /// does not trigger a connection by itself.
  Future<String?> lastKnownDeviceAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastDeviceAddressKey);
  }

  /// A single, explicit connection attempt. Does not retry on failure or on
  /// a later drop — the UI is responsible for calling this again if the
  /// user wants to try again.
  Future<void> connect(DiscoveredDevice device) async {
    state = BluetoothConnectionState(
      status: BluetoothConnectionStatus.connecting,
      deviceName: device.name,
      deviceAddress: device.address,
    );

    final BluetoothConnection connection;
    try {
      final result = await _plugin.connect(device.address);
      if (result == null) {
        throw StateError('connect() returned null');
      }
      connection = result;
    } catch (error) {
      debugPrint('BluetoothConnectionService: connect() failed: $error');
      state = BluetoothConnectionState(
        status: BluetoothConnectionStatus.failed,
        deviceName: device.name,
        deviceAddress: device.address,
        lastError: error.toString(),
      );
      return;
    }

    _connection = connection;
    _inputSubscription = connection.input?.listen(
      _incomingBytesController.add,
      onDone: () => _handleDrop(reason: 'input stream closed (onDone)'),
      onError: (Object error) => _handleDrop(reason: error.toString()),
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastDeviceAddressKey, device.address);

    state = BluetoothConnectionState(
      status: BluetoothConnectionStatus.connected,
      deviceName: device.name,
      deviceAddress: device.address,
    );
  }

  Future<void> disconnect() async {
    // Cancel our own subscription *before* tearing down the connection —
    // otherwise finishing the connection can make its input stream
    // close/error, which would surface through to _handleDrop() as if the
    // link had dropped unexpectedly instead of being closed on purpose.
    await _inputSubscription?.cancel();
    await _connection?.finish();
    _connection = null;
    state = const BluetoothConnectionState(
      status: BluetoothConnectionStatus.disconnected,
    );
  }

  /// Writes a raw string to the connection. Silently drops the write if
  /// there is no active connection — callers never need to check connection
  /// state before writing.
  void send(String raw) {
    try {
      _connection?.writeString(raw);
    } on StateError {
      // Connection dropped mid-write; the input stream's onDone/onError
      // (wired above) surfaces the drop separately.
    }
  }

  void _handleDrop({String? reason}) {
    debugPrint('BluetoothConnectionService: connection dropped: $reason');
    _inputSubscription?.cancel();
    _connection?.dispose();
    _connection = null;
    state = BluetoothConnectionState(
      status: BluetoothConnectionStatus.disconnected,
      deviceName: state.deviceName,
      deviceAddress: state.deviceAddress,
      lastError: reason,
    );
  }
}

final bluetoothConnectionServiceProvider =
    NotifierProvider<BluetoothConnectionService, BluetoothConnectionState>(
      BluetoothConnectionService.new,
    );
