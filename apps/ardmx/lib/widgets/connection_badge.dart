import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bluetooth/bluetooth_connection_state.dart';
import '../core/bluetooth/bluetooth_error_messages.dart';
import '../state/providers.dart';

/// Persistent connection status indicator shown on every screen (not just
/// Splash), since the Bluetooth link can drop mid-session while the user is
/// anywhere in the app.
class ConnectionBadge extends ConsumerWidget {
  const ConnectionBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(bluetoothConnectionServiceProvider);
    // Connection-status colors (green/orange/red/grey) are intentionally
    // literal rather than theme-derived — like the on/off indicators in
    // ArdmxEvoCycleProgrammingScreen, they signal a universal
    // good/warning/bad state, not a brand/UI role, so they must stay fixed
    // regardless of the app's purple theme.
    return switch (connection.status) {
      BluetoothConnectionStatus.connected => _Badge(
        icon: Icons.bluetooth_connected,
        color: Colors.green,
        label: connection.deviceName ?? 'Connectat',
      ),
      BluetoothConnectionStatus.connecting => const _Badge(
        icon: Icons.bluetooth_searching,
        color: Colors.orange,
        label: 'Connectant...',
      ),
      BluetoothConnectionStatus.failed => _Badge(
        icon: Icons.bluetooth_disabled,
        color: Colors.red,
        label: friendlyBluetoothError(connection.lastError),
        details: connection.lastError,
      ),
      BluetoothConnectionStatus.permissionDenied => const _Badge(
        icon: Icons.bluetooth_disabled,
        color: Colors.red,
        label: 'Permís denegat',
      ),
      BluetoothConnectionStatus.disconnected => _Badge(
        icon: Icons.bluetooth_disabled,
        color: Colors.grey,
        label: connection.lastError == null
            ? 'Sense connexió'
            : friendlyBluetoothError(connection.lastError),
        details: connection.lastError,
      ),
      BluetoothConnectionStatus.idle => const _Badge(
        icon: Icons.bluetooth_disabled,
        color: Colors.grey,
        label: 'Sense connexió',
      ),
    };
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.color,
    required this.label,
    this.details,
  });

  final IconData icon;
  final Color color;
  final String label;

  /// Raw technical detail (e.g. the underlying exception message), shown
  /// via a long-press tooltip instead of cluttering the badge itself.
  final String? details;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Smaller than the AppBar's 24px back/logout IconButtons on
          // purpose — this is a compact status pill sized to match its own
          // 12px label, not a tap target.
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 4),
          // Constrained so a long message can never overflow the AppBar —
          // it truncates with an ellipsis instead. The full, untruncated
          // text is still what a screen reader announces (see the
          // Semantics wrapper below), so nothing is lost there even when
          // this clips visually.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
    // "Bluetooth: " prefix since this badge otherwise has no visible title
    // — without it, a screen reader would just announce e.g. "Connectant…"
    // with no indication of what that's the status of.
    final labeled = Semantics(label: 'Bluetooth: $label', child: content);
    return details == null
        ? labeled
        : Tooltip(message: details!, child: labeled);
  }
}
