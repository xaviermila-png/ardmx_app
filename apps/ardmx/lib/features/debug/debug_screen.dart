import 'package:flutter/material.dart';

import '../../routing/app_router.dart';
import '../../widgets/app_scaffold.dart';

/// Offline navigation shortcut — jumps straight into a product's screen
/// tree without a real BLE connection, so the app's screen flow can be
/// demoed (e.g. at a fair/exhibition stand) without any hardware nearby.
/// Every screen already tolerates being disconnected (writes/requests are
/// fire-and-forget and silently no-op — see [BluetoothConnectionService]),
/// so this is just a router shortcut, not a special "demo mode": values
/// simply stay at their placeholder '—' state. Reached via long-press on
/// the Splash logo.
class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Navegació sense connexió',
      onBack: () => Navigator.of(context).pop(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Entra directament a l\'arbre de pantalles d\'un producte, '
                'sense connectar cap dispositiu — útil per ensenyar la '
                'navegació.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 260,
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.ardmx4EvoMainMenu),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('ARDMX4 EVO'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 260,
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.ardmxOne),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('ARDMX One'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
