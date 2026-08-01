/// Which underlying Bluetooth technology a [DiscoveredDevice]/connection
/// uses — Classic (SPP, the Mega/HC-06) or BLE (GATT, the ESP32 boards,
/// since `ardmx-one-firmware`'s migration off Bluetooth Classic).
enum TransportKind { classic, ble }

/// A device the app can connect to, from either transport — Classic devices
/// come from Android's paired-device list ([BluetoothConnectionService.
/// pairedDevices]), BLE devices from a live scan ([BluetoothConnectionService
/// .bleScanResults]). Deliberately doesn't carry either plugin's own device
/// object: everything above the transport layer only ever needs an address +
/// display name, regardless of which transport found it.
class DiscoveredDevice {
  const DiscoveredDevice({required this.kind, required this.address, this.name});

  final TransportKind kind;
  final String address;
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is DiscoveredDevice &&
      other.kind == kind &&
      other.address == address;

  @override
  int get hashCode => Object.hash(kind, address);
}

/// A single active connection to one device, abstracting over Classic (SPP)
/// vs BLE (GATT) — see `ClassicBluetoothTransport`/`BleBluetoothTransport`.
/// [BluetoothConnectionService] constructs exactly one of these per
/// [DiscoveredDevice.kind] and re-exposes [incomingBytes]/[send] unchanged
/// regardless of which implementation is active, so `VirtuinoProtocol` (and
/// everything built on top of it — every screen, [AppStateNotifier],
/// [DeviceIdentificationService]) never needs to know or care which
/// transport is in use.
abstract class BluetoothTransport {
  /// Raw bytes received from the device, in whatever chunks the underlying
  /// transport happens to deliver them (one Classic SPP read, or one BLE
  /// notify packet). `VirtuinoFrameCodec` already handles frame boundaries
  /// never lining up with chunk boundaries, so implementations don't need to
  /// do any reassembly of their own before exposing this — including BLE's
  /// long replies that arrive fragmented across several notify packets (see
  /// `ardmx-one-firmware`'s own `sendFrame()`, which fragments the same way
  /// on the way out).
  Stream<List<int>> get incomingBytes;

  /// Establishes the connection. Throws on failure — callers (currently only
  /// [BluetoothConnectionService.connect]) catch and translate to
  /// [BluetoothConnectionStatus.failed].
  Future<void> connect();

  /// Tears down the connection. Callers must cancel their subscription to
  /// [incomingBytes] *before* calling this (see
  /// [BluetoothConnectionService.disconnect]) — otherwise the disconnect
  /// itself can surface as a spurious "unexpected drop" through the same
  /// stream closing/erroring.
  Future<void> disconnect();

  /// Writes a raw string to the connection. Silently drops the write if
  /// there is no active connection — callers never need to check connection
  /// state before writing.
  void send(String raw);

  /// Releases any resources (stream controllers, subscriptions) — called
  /// once this transport is no longer needed (a new one is constructed for
  /// the next connection attempt, transports are single-use).
  void dispose();
}
