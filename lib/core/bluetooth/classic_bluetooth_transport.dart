import 'dart:async';

import 'package:flutter_blue_classic/flutter_blue_classic.dart';

import 'bluetooth_transport.dart';

/// Bluetooth Classic (SPP) transport — the Mega/HC-06. Same logic
/// [BluetoothConnectionService] used to own directly before the BLE
/// migration, just extracted behind [BluetoothTransport] unchanged.
class ClassicBluetoothTransport implements BluetoothTransport {
  ClassicBluetoothTransport(this._plugin, this.address);

  final FlutterBlueClassic _plugin;
  final String address;

  BluetoothConnection? _connection;
  StreamSubscription<List<int>>? _inputSubscription;
  final _incomingBytesController = StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> get incomingBytes => _incomingBytesController.stream;

  @override
  Future<void> connect() async {
    final connection = await _plugin.connect(address);
    if (connection == null) {
      throw StateError('connect() returned null');
    }
    _connection = connection;
    _inputSubscription = connection.input?.listen(
      _incomingBytesController.add,
      onDone: () => _incomingBytesController.close(),
      onError: _incomingBytesController.addError,
    );
  }

  @override
  Future<void> disconnect() async {
    await _inputSubscription?.cancel();
    await _connection?.finish();
    _connection = null;
  }

  @override
  void send(String raw) {
    try {
      _connection?.writeString(raw);
    } on StateError {
      // Connection dropped mid-write; the input stream's onDone/onError
      // (wired above) surfaces the drop separately.
    }
  }

  @override
  void dispose() {
    _inputSubscription?.cancel();
    _connection?.dispose();
    _incomingBytesController.close();
  }
}
