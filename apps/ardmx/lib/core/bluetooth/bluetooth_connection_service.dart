import 'dart:async';

import 'package:flutter/widgets.dart' show debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_bluetooth_transport.dart';
import 'bluetooth_connection_state.dart';

/// A BLE device found by [BluetoothConnectionService.bleScanResults] —
/// address + advertised name, nothing plugin-specific (everything above
/// this layer only ever needs those two things to connect and display a
/// picker).
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

/// Owns the single BLE connection to a device (ARDMX One or ARDMX4 EVO —
/// see [DeviceIdentificationService] for telling them apart once
/// connected). This app has no other transport — see
/// [BleBluetoothTransport]'s own doc comment for why there's no abstract
/// transport interface here, unlike the combined app this was split from.
///
/// Connecting and disconnecting are both fully explicit user actions: there
/// is no auto-connect on launch and no automatic reconnect on drop. This is
/// deliberate (simplified while diagnosing a real HC-05 connectivity issue
/// on the sibling Classic app) — auto-retry logic was found to make
/// failures harder to reproduce/diagnose by hammering the module with rapid
/// reconnect attempts.
class BluetoothConnectionService extends Notifier<BluetoothConnectionState> {
  static const _lastDeviceAddressKey = 'last_bluetooth_device_address';

  final StreamController<List<int>> _incomingBytesController =
      StreamController<List<int>>.broadcast();

  BleBluetoothTransport? _activeTransport;
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
      _activeTransport?.dispose();
      _incomingBytesController.close();
    });
    return BluetoothConnectionState.initial;
  }

  /// Live BLE scan results, filtered to only devices advertising the ARDMX
  /// GATT service ([BleBluetoothTransport.serviceUuid]) — this app never
  /// bonds/pairs devices via Android settings, it scans fresh every time.
  Stream<List<DiscoveredDevice>> get bleScanResults =>
      fbp.FlutterBluePlus.scanResults.map(
        (results) => [
          for (final result in results)
            DiscoveredDevice(
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

    final transport = BleBluetoothTransport(device.address);

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
    // purpose.
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
