import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bluetooth/bluetooth_connection_state.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import '../main_menu/widgets/cycle_progress_bar.dart';
import '../main_menu/widgets/dial_selector.dart';
import 'widgets/ardmx_one_v2_config_submenu.dart';

/// Home screen for the ARDMX One v2 tree — same V9-V50 dial/cycle protocol
/// as the ARDMX EVO tree's own [ArdmxEvoMainMenuScreen] (that's the whole
/// point of adopting its exact scene/cycle indices — see
/// ardmx-one-firmware/src/main.cpp), minus anything song/volume-related:
/// this hardware has no DFPlayer. [DialSelector.showManual] is `false` for
/// the same reason (Trigger mode needs a physical pin this board doesn't
/// have either).
class ArdmxOneV2MainMenuScreen extends ConsumerStatefulWidget {
  const ArdmxOneV2MainMenuScreen({super.key});

  @override
  ConsumerState<ArdmxOneV2MainMenuScreen> createState() =>
      _ArdmxOneV2MainMenuScreenState();
}

class _ArdmxOneV2MainMenuScreenState
    extends ConsumerState<ArdmxOneV2MainMenuScreen> {
  void _goToConnectionScreen(BuildContext context) {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.splash, (route) => false);
  }

  Future<void> _exit(WidgetRef ref) async {
    final status = ref.read(bluetoothConnectionServiceProvider).status;
    if (status == BluetoothConnectionStatus.connected) {
      await ref.read(bluetoothConnectionServiceProvider.notifier).disconnect();
    }
    SystemNavigator.pop();
  }

  static Widget _submenu(double squareSize, double spacing) =>
      ArdmxOneV2ConfigSubmenu(squareSize: squareSize, spacing: spacing);

  @override
  Widget build(BuildContext context) {
    final currentMode = ref.watch(
      appStateProvider.select((s) => s.mainSelector),
    );
    final currentLabel = DialSelector.labelFor(currentMode) ?? '';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goToConnectionScreen(context);
      },
      child: AppScaffold(
        title: 'Menú Principal',
        onBack: () => _goToConnectionScreen(context),
        onExit: () => _exit(ref),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            children: [
              Text(
                currentLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(flex: 1),
              const CycleProgressBar(),
              const SizedBox(height: 20),
              const Divider(thickness: 1, height: 1),
              const SizedBox(height: 20),
              const DialSelector(submenuBuilder: _submenu, showManual: false),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
