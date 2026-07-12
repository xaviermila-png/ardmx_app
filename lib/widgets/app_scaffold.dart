import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bluetooth/bluetooth_connection_state.dart';
import '../routing/app_router.dart';
import '../state/providers.dart';
import 'connection_badge.dart';

/// Thin shared Scaffold so every screen shows the same [ConnectionBadge] and
/// [_DisconnectHomeButton] in its AppBar without repeating the wiring.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: const [
          _DisconnectHomeButton(),
          ConnectionBadge(),
          SizedBox(width: 8),
        ],
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Disconnects the Bluetooth link and returns to Splash. Only shown while
/// connected — there was previously no way back to Splash from Main Menu
/// (it replaced Splash in the navigation stack), which meant the only way
/// to disconnect was quitting the whole app.
class _DisconnectHomeButton extends ConsumerWidget {
  const _DisconnectHomeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(
      bluetoothConnectionServiceProvider.select(
        (s) => s.status == BluetoothConnectionStatus.connected,
      ),
    );
    if (!connected) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.home),
      tooltip: "Desconnectar i tornar a l'inici",
      onPressed: () async {
        await ref.read(bluetoothConnectionServiceProvider.notifier).disconnect();
        if (context.mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.splash, (route) => false);
        }
      },
    );
  }
}
