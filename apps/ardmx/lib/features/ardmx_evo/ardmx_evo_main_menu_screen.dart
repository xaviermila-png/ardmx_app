import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bluetooth/bluetooth_connection_state.dart';
import '../../core/constants/v_map.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import '../main_menu/widgets/cycle_progress_bar.dart';
import '../main_menu/widgets/dial_selector.dart';
import '../main_menu/widgets/volume_slider.dart';
import 'widgets/ardmx_evo_config_submenu.dart';

/// Home screen for the ARDMX EVO tree — same layout/logic as [MainMenuScreen]
/// (same V0-V50 dial/cycle/volume protocol), duplicated per the project's own
/// separate-navigation-per-product decision, pointing its "Configuració"
/// submenu at the EVO tree's own routes via [DialSelector.submenuBuilder].
class ArdmxEvoMainMenuScreen extends ConsumerStatefulWidget {
  const ArdmxEvoMainMenuScreen({super.key});

  @override
  ConsumerState<ArdmxEvoMainMenuScreen> createState() =>
      _ArdmxEvoMainMenuScreenState();
}

class _ArdmxEvoMainMenuScreenState
    extends ConsumerState<ArdmxEvoMainMenuScreen> {
  static const _pollInterval = Duration(milliseconds: 800);

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // This screen has no poll loop of its own otherwise — only needed here
    // to show the "Cançó: X" label next to Volum, same as Cycle
    // Programming (which polls this V0 itself already).
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _poll() {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    ref.read(protocolProvider).requestV(VIndex.songNumber);
  }

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
      ArdmxEvoConfigSubmenu(squareSize: squareSize, spacing: spacing);

  @override
  Widget build(BuildContext context) {
    final currentMode = ref.watch(
      appStateProvider.select((s) => s.mainSelector),
    );
    final currentLabel = DialSelector.labelFor(currentMode) ?? '';
    final songNumber = ref.watch(appStateProvider.select((s) => s.songNumber));

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
              const DialSelector(submenuBuilder: _submenu),
              const SizedBox(height: 24),
              VolumeSlider(
                titleFontSize: 14,
                titleAlignment: Alignment.bottomRight,
                leadingAlignment: Alignment.bottomLeft,
                titleRowHeight: 20,
                thumbSize: 30,
                leading: Text(
                  songNumber == null || songNumber == 0
                      ? 'Cançó: Off'
                      : 'Cançó: $songNumber',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
