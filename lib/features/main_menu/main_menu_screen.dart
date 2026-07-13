import 'package:flutter/material.dart';

import '../../routing/app_router.dart';
import '../../widgets/app_scaffold.dart';
import 'widgets/cycle_progress_bar.dart';
import 'widgets/dial_selector.dart';
import 'widgets/volume_slider.dart';

class MainMenuScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
        title: 'Menú Principal ARDMX4',
        automaticallyImplyLeading: false,
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        floatingActionButton: FloatingActionButton(
          onPressed: () => _goToConnectionScreen(context),
          tooltip: 'Tornar a la pantalla de connexió',
          child: const Icon(Icons.arrow_back),
        ),
        // The whole block (progress bar + dial grid + volume) is
        // bottom-justified — the Spacer goes first so empty space collects
        // above it. The progress bar sits right above the button grid with
        // just a small gap, not pinned to the very top of the screen.
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          child: Column(
            children: [
              const Spacer(flex: 4),
              const CycleProgressBar(),
              const SizedBox(height: 20),
              const Divider(color: Colors.black, thickness: 1, height: 1),
              const SizedBox(height: 20),
              const DialSelector(),
              const SizedBox(height: 24),
              const VolumeSlider(),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
