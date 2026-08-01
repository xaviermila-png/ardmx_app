import 'dart:async';

import 'package:flutter/widgets.dart' show debugPrint;
import 'package:flutter_blue_classic/flutter_blue_classic.dart' show FlutterBlueClassic, BluetoothDevice;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_bluetooth_transport.dart';
import 'bluetooth_connection_state.dart';
import 'bluetooth_transport.dart';
import 'classic_bluetooth_transport.dart';

/// Owns the single connection to a device — either Bluetooth Classic (SPP,
/// the Mega/HC-06) or BLE (GATT, the ESP32 boards). The underlying transport
/// ([ClassicBluetoothTransport]/[BleBluetoothTransport]) is an internal
/// implementation detail picked per-connection from [DiscoveredDevice.kind]
/// — everything above this class (`VirtuinoProtocol`, every screen) only
/// ever sees [incomingBytes]/[send]/[BluetoothConnectionState], unchanged
/// regardless of which transport is active. See [connect].
///
/// Connecting and disconnecting are both fully explicit user actions: there
/// is no auto-connect on launch and no automatic reconnect on drop. This is
/// deliberate (simplified while diagnosing a real HC-05 connectivity issue)
/// — auto-retry logic was found to make failures harder to reproduce/
/// diagnose by hammering the module with rapid reconnect attempts.
class BluetoothConnectionService extends Notifier<BluetoothConnectionState> {
  static const _lastDeviceAddressKey = 'last_bluetooth_device_address';

  final FlutterBlueClassic _classicPlugin = FlutterBlueClassic();
  final StreamController<List<int>> _incomingBytesController =
      StreamController<List<int>>.broadcast();

  BluetoothTransport? _activeTransport;
  StreamSubscription<List<int>>? _inputSubscription;

  /// Broadcast stream of raw bytes received from the connected device.
  /// Outlives any individual connection (Classic or BLE) — [VirtuinoProtocol]
  /// is built on top of this once and doesn't need to be recreated when the
  /// user disconnects and reconnects, or switches between a Classic and a
  /// BLE device across sessions.
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
      _activeTransport?.dispose();
      _incomingBytesController.close();
    });
    return BluetoothConnectionState.initial;
  }

  Future<List<DiscoveredDevice>> pairedDevices() async {
    final devices = await _classicPlugin.bondedDevices ?? const [];
    return [
      for (final device in devices)
        DiscoveredDevice(
          kind: TransportKind.classic,
          address: device.address,
          name: device.name,
        ),
    ];
  }

  /// Active discovery scan (Classic only) — only used by the Debug screen's
  /// "Refrescar nom" button, to nudge Android into re-reading a bonded
  /// device's current advertised name (e.g. after an ARDMX One rename)
  /// without forgetting/re-pairing it. Everywhere else in the app
  /// deliberately only ever talks to already-bonded Classic devices and
  /// never scans; this is a narrow, opt-in exception to that rule, not a
  /// reversal of it. Not guaranteed to update Android's persisted
  /// paired-device name on every OS version/OEM — forgetting and re-pairing
  /// remains the reliable fallback. Unrelated to [bleScanResults]/
  /// [startBleScan] below — BLE devices aren't bonded/paired at all in this
  /// app's model, they're found by live scan every time.
  void startScan() => _classicPlugin.startScan();

  void stopScan() => _classicPlugin.stopScan();

  Stream<BluetoothDevice> get scanResults => _classicPlugin.scanResults;

  /// Live BLE scan results, filtered to only devices advertising the ARDMX
  /// GATT service ([BleBluetoothTransport.serviceUuid]) — unlike Classic,
  /// BLE devices in this app are never bonded/paired via Android settings;
  /// the connection screen's BLE section scans fresh every time (see
  /// [startBleScan]).
  Stream<List<DiscoveredDevice>> get bleScanResults =>
      fbp.FlutterBluePlus.scanResults.map(
        (results) => [
          for (final result in results)
            DiscoveredDevice(
              kind: TransportKind.ble,
              address: result.device.remoteId.str,
              name: result.advertisementData.advName.isNotEmpty
                  ? result.advertisementData.advName
                  : null,
            ),
        ],
      );

  Future<void> startBleScan() => fbp.FlutterBluePlus.startScan(
    withServices: [BleBluetoothTransport.serviceUuid],
    timeout: const Duration(seconds: 10),
  );

  Future<void> stopBleScan() => fbp.FlutterBluePlus.stopScan();

  /// The address of the last device a connection was ever successfully
  /// established with, purely to pre-select it in the device picker —
  /// does not trigger a connection by itself. Shared between both
  /// transports (an address is unambiguous either way — Classic uses MAC,
  /// BLE uses MAC on Android too).
  Future<String?> lastKnownDeviceAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastDeviceAddressKey);
  }

  /// A single, explicit connection attempt to either a Classic or a BLE
  /// device (see [DiscoveredDevice.kind]). Does not retry on failure or on
  /// a later drop — the UI is responsible for calling this again if the
  /// user wants to try again.
  Future<void> connect(DiscoveredDevice device) async {
    state = BluetoothConnectionState(
      status: BluetoothConnectionStatus.connecting,
      deviceName: device.name,
      deviceAddress: device.address,
    );

    final transport = device.kind == TransportKind.classic
        ? ClassicBluetoothTransport(_classicPlugin, device.address)
        : BleBluetoothTransport(device.address);

    try {
      await transport.connect();
    } catch (error) {
      debugPrint('BluetoothConnectionService: connect() failed: $error');
      transport.dispose();
      state = BluetoothConnectionState(
        status: BluetoothConnectionStatus.failed,
        deviceName: device.name,
        deviceAddress: device.address,
        lastError: error.toString(),
      );
      return;
    }

    _activeTransport = transport;
    _inputSubscription = transport.incomingBytes.listen(
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
    // Cancel our own subscription *before* tearing down the transport —
    // otherwise the transport's own disconnect() can make its incomingBytes
    // stream close/error, which would surface through to _handleDrop() as
    // if the link had dropped unexpectedly instead of being closed on
    // purpose (same ordering the old Classic-only code relied on).
    await _inputSubscription?.cancel();
    await _activeTransport?.disconnect();
    _activeTransport?.dispose();
    _activeTransport = null;
    state = const BluetoothConnectionState(
      status: BluetoothConnectionStatus.disconnected,
    );
  }

  /// Writes a raw string to the connection. Silently drops the write if
  /// there is no active connection — callers never need to check connection
  /// state before writing.
  void send(String raw) => _activeTransport?.send(raw);

  void _handleDrop({String? reason}) {
    debugPrint('BluetoothConnectionService: connection dropped: $reason');
    _inputSubscription?.cancel();
    _activeTransport?.dispose();
    _activeTransport = null;
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
