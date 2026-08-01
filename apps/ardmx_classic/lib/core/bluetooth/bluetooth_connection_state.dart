enum BluetoothConnectionStatus {
  /// Nothing has happened yet (app just launched, permissions not checked).
  idle,

  /// Bluetooth permission was denied (temporarily or permanently).
  permissionDenied,

  /// Not connected: no connection attempted yet, or the user explicitly
  /// disconnected, or a connection dropped and was not retried.
  disconnected,

  /// A connection attempt (explicitly started by the user) is in flight.
  connecting,

  connected,

  /// The most recent explicit connect attempt failed.
  failed,
}

class BluetoothConnectionState {
  const BluetoothConnectionState({
    required this.status,
    this.deviceName,
    this.deviceAddress,
    this.lastError,
  });

  static const initial = BluetoothConnectionState(
    status: BluetoothConnectionStatus.idle,
  );

  final BluetoothConnectionStatus status;
  final String? deviceName;
  final String? deviceAddress;

  /// The message from the most recent failed connect attempt or unexpected
  /// drop, if any. Surfaced in the UI (debug screen, connection badge)
  /// since silently swallowing this made a real hardware-compatibility
  /// failure undiagnosable in practice.
  final String? lastError;

  BluetoothConnectionState copyWith({
    BluetoothConnectionStatus? status,
    String? deviceName,
    String? deviceAddress,
    String? lastError,
  }) {
    return BluetoothConnectionState(
      status: status ?? this.status,
      deviceName: deviceName ?? this.deviceName,
      deviceAddress: deviceAddress ?? this.deviceAddress,
      lastError: lastError ?? this.lastError,
    );
  }
}
