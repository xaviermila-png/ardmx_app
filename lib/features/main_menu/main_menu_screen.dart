import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bluetooth/bluetooth_connection_state.dart';
import '../../core/constants/v_map.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import 'widgets/config_submenu.dart';
import 'widgets/dial_selector.dart';
import 'widgets/volume_slider.dart';

class MainMenuScreen extends ConsumerWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mainSelector = ref.watch(
      appStateProvider.select((s) => s.mainSelector),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Main Menu is always the base of the nav stack (Splash is
        // replaced, not pushed, when connecting), so a back-button press
        // here always means the user is about to exit the app. Force a
        // clean disconnect first and *wait* for it — relying only on the
        // app-lifecycle pause/detach hook was observed to not reliably
        // disconnect in time when exiting via the back button.
        if (ref.read(bluetoothConnectionServiceProvider).status ==
            BluetoothConnectionStatus.connected) {
          await ref
              .read(bluetoothConnectionServiceProvider.notifier)
              .disconnect();
        }
        SystemNavigator.pop();
      },
      child: AppScaffold(
        title: 'Menú Principal',
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const DialSelector(),
              const SizedBox(height: 24),
              const VolumeSlider(),
              const SizedBox(height: 24),
              if (mainSelector == MainSelectorMode.configuration.vValue)
                const ConfigSubmenu(),
            ],
          ),
        ),
      ),
    );
  }
}
