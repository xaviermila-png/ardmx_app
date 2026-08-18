import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

/// BLE (GATT) transport — the only transport this app speaks (ARDMX One and
/// ARDMX EVO, both ESP32). UUIDs must match those firmwares' own
/// `BLE_SERVICE_UUID`/`BLE_WRITE_CHAR_UUID`/`BLE_NOTIFY_CHAR_UUID` exactly
/// (see either firmware's `main.cpp` header comment for the full GATT
/// design/rationale — deliberately the same UUIDs on both, so one scan
/// finds either product).
///
/// The Mega (ardmx4-firmware, Bluetooth Classic) is a different app now
/// ("ARDMX Classic") — this app has no Classic transport at all, unlike the
/// combined app this was split from, so there's no abstract transport
/// interface here either, just this one concrete class used directly by
/// [BluetoothConnectionService].
class BleBluetoothTransport {
  BleBluetoothTransport(this.address);

  final String address;

  /// Public so [BluetoothConnectionService] can filter its BLE scan to only
  /// devices advertising this service — every ARDMX ESP32 board, nothing
  /// else nearby.
  static final fbp.Guid serviceUuid = fbp.Guid(
    '74fdf89b-a063-48f4-837d-03462d2b3687',
  );
  static final fbp.Guid _writeCharUuid = fbp.Guid(
    'c7e05764-94cb-4a2f-8cd4-4751163c58ad',
  );
  static final fbp.Guid _notifyCharUuid = fbp.Guid(
    'dd2a9ece-4964-4f42-b986-36719d38b2a3',
  );

  late final fbp.BluetoothDevice _device;
  fbp.BluetoothCharacteristic? _writeCharacteristic;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionStateSubscription;
  final _incomingBytesController = StreamController<List<int>>.broadcast();

  Stream<List<int>> get incomingBytes => _incomingBytesController.stream;

  Future<void> connect() async {
    _device = fbp.BluetoothDevice.fromId(address);

    // mtu:512 (the default) has connect() request a larger ATT MTU than the
    // BLE-spec minimum right away — the firmware's sendFrame() fragments
    // correctly either way (confirmed on real hardware even at the 23-byte
    // minimum), this just reduces packet count for long replies (V69) when
    // the negotiation succeeds.
    await _device.connect();

    // Subscribed only *after* connect() succeeds, deliberately: this stream
    // replays a cached "initial value" the instant anything listens
    // (flutter_blue_plus's own newStreamWithInitialValue), and before the
    // very first successful connection that cached value is `disconnected`
    // — subscribing earlier fired this listener immediately with
    // `disconnected` and closed `_incomingBytesController` before any real
    // data could ever flow through it, which looked like every connection
    // instantly dropping. Confirmed on real hardware: no notification was
    // ever received, not even the ones the firmware demonstrably sent
    // (validated separately via nRF Connect) — subscribing after connect()
    // fixed it, since by then the replayed "initial value" is genuinely
    // `connected`.
    _connectionStateSubscription = _device.connectionState.listen((state) {
      if (state == fbp.BluetoothConnectionState.disconnected) {
        _incomingBytesController.close();
      }
    });

    final services = await _device.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid == serviceUuid,
      orElse: () => throw StateError(
        'Servei ARDMX (BLE) no trobat — firmware antic o dispositiu equivocat?',
      ),
    );
    _writeCharacteristic = service.characteristics.firstWhere(
      (c) => c.uuid == _writeCharUuid,
      orElse: () => throw StateError(
        'Característica d\'escriptura BLE no trobada',
      ),
    );
    final notifyCharacteristic = service.characteristics.firstWhere(
      (c) => c.uuid == _notifyCharUuid,
      orElse: () => throw StateError(
        'Característica de notificació BLE no trobada',
      ),
    );

    _notifySubscription = notifyCharacteristic.onValueReceived.listen(
      _incomingBytesController.add,
    );
    // Subscribing is a separate step from finding the characteristic — BLE
    // notify() on the firmware side is a no-op until the app explicitly
    // writes its CCCD (see ardmx-one-firmware's header comment), unlike SPP
    // which is a continuous stream the moment the socket is open.
    final subscribed = await notifyCharacteristic.setNotifyValue(true);
    if (!subscribed) {
      throw StateError('No s\'ha pogut subscriure a les notificacions BLE');
    }
  }

  Future<void> disconnect() async {
    await _connectionStateSubscription?.cancel();
    await _notifySubscription?.cancel();
    await _device.disconnect();
  }

  void send(String raw) {
    final characteristic = _writeCharacteristic;
    if (characteristic == null) return;
    // withoutResponse: true matches the firmware's WRITE_NR property — same
    // "fire and forget" spirit as Classic's writeString(), no ack expected
    // at this layer (the protocol's own replies, if any, arrive later via
    // the notify characteristic like any other update).
    characteristic.write(utf8.encode(raw), withoutResponse: true);
  }

  void dispose() {
    _connectionStateSubscription?.cancel();
    _notifySubscription?.cancel();
    _incomingBytesController.close();
  }
}
