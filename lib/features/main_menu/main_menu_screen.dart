import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import 'widgets/config_submenu.dart';
import 'widgets/dial_selector.dart';
import 'widgets/volume_slider.dart';

class MainMenuScreen extends ConsumerWidget {
  const MainMenuScreen({super.key});

  /// Returns to the connection (Splash) screen without touching the
  /// Bluetooth link — leaving it connected. The only actions that actually
  /// disconnect are Splash's own back-button/"Sortir", never simply
  /// navigating away from Main Menu.
  void _goToConnectionScreen(BuildContext context) {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.splash, (route) => false);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mainSelector = ref.watch(
      appStateProvider.select((s) => s.mainSelector),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Main Menu is the base of the nav stack, so a back-button press
        // here would otherwise exit the app. Instead it just goes back to
        // the connection screen, same as the bottom-left button — leaving
        // the app via Home/Recents is left to Android's normal behavior
        // and never disconnects either.
        if (!didPop) _goToConnectionScreen(context);
      },
      child: AppScaffold(
        title: 'Menú Principal',
        automaticallyImplyLeading: false,
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        floatingActionButton: FloatingActionButton(
          onPressed: () => _goToConnectionScreen(context),
          tooltip: 'Tornar a la pantalla de connexió',
          child: const Icon(Icons.arrow_back),
        ),
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
