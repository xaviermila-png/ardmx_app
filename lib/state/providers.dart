import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bluetooth/bluetooth_connection_service.dart';
import '../core/protocol/virtuino_protocol.dart';
import 'app_state.dart';
import 'app_state_notifier.dart';

export '../core/bluetooth/bluetooth_connection_service.dart'
    show bluetoothConnectionServiceProvider;
export '../core/bluetooth/bluetooth_transport.dart'
    show DiscoveredDevice, TransportKind;
export '../core/bluetooth/device_identification_service.dart'
    show DeviceType, deviceIdentificationServiceProvider;

/// Built once on top of [BluetoothConnectionService.incomingBytes], which
/// itself survives reconnects — so this provider never needs to be rebuilt
/// when the Bluetooth link drops and comes back.
final protocolProvider = Provider<VirtuinoProtocol>((ref) {
  final service = ref.watch(bluetoothConnectionServiceProvider.notifier);
  final protocol = VirtuinoProtocol(
    input: service.incomingBytes,
    output: service.send,
  );
  ref.onDispose(protocol.dispose);
  return protocol;
});

final appStateProvider = NotifierProvider<AppStateNotifier, AppState>(
  AppStateNotifier.new,
);
