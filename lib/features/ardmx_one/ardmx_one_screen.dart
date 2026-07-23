import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bluetooth/bluetooth_connection_state.dart';
import '../../core/constants/v_map.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import '../scene_channels/widgets/channel_sliders.dart';
import 'widgets/channel_number_bar.dart';

/// Home screen for ARDMX One devices (single static scene, no music/cycle) —
/// deliberately separate from [SceneChannelsScreen]/[MainMenuScreen], which
/// are built around the ARDMX4's scenes/cycle/transitions. This is the base
/// of the nav stack for this device type, reached directly from Splash (see
/// its device-name-based redirect), the same role Main Menu plays for
/// ARDMX4.
///
/// Reuses [ChannelSliders] as-is (only ever reads/writes V1-V3, identical on
/// both firmwares) but has its own, bigger channel bar ([ChannelNumberBar])
/// showing the 3 selected channel numbers directly, since this screen has no
/// scene bar or transition-mode selector competing for vertical space.
class ArdmxOneScreen extends ConsumerStatefulWidget {
  const ArdmxOneScreen({super.key});

  @override
  ConsumerState<ArdmxOneScreen> createState() => _ArdmxOneScreenState();
}

class _ArdmxOneScreenState extends ConsumerState<ArdmxOneScreen> {
  static const _pollInterval = Duration(milliseconds: 400);

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Same "nothing is pushed unsolicited" pattern as every other screen —
    // see SceneChannelsScreen for the full reasoning. Deferred a frame since
    // _poll() needs ModalRoute.of(context), not resolvable inside initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _poll() {
    // Only the topmost route should poll — see SceneChannelsScreen/RgbWheel
    // for why two screens polling at once corrupts the wire protocol.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;

    // No activeScene/transitionMode requests here: ARDMX One has neither.
    ref.read(protocolProvider).requestAll([
      VIndex.channel1Number,
      VIndex.channel2Number,
      VIndex.channel3Number,
      VIndex.channel1Value,
      VIndex.channel2Value,
      VIndex.channel3Value,
    ]);
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Base of the nav stack for this device type (like Main Menu is for
        // ARDMX4): back goes to the connection screen, not out of the app.
        if (!didPop) _goToConnectionScreen(context);
      },
      child: AppScaffold(
        title: 'ARDMX One',
        automaticallyImplyLeading: false,
        body: Column(
          children: [
            const ChannelNumberBar(),
            Expanded(
              child: Center(
                // Fixed (rather than filling all leftover space): the user
                // asked for shorter sliders/boxes than this screen's default
                // Expanded sizing would give them.
                child: SizedBox(
                  height: 392,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: ChannelSliders(valueFontSize: 26),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton(
                    heroTag: 'ardmxOneBack',
                    onPressed: () => _goToConnectionScreen(context),
                    tooltip: 'Tornar a la pantalla de connexió',
                    child: const Icon(Icons.arrow_back),
                  ),
                  FloatingActionButton(
                    heroTag: 'ardmxOneConfig',
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.ardmxOneConfig),
                    tooltip: 'Configuració',
                    child: const Icon(Icons.settings),
                  ),
                  // RGB access stacked above Sortir, freeing horizontal room
                  // now that the sliders take up less height.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        heroTag: 'ardmxOneRgbWheel',
                        onPressed: () => Navigator.of(
                          context,
                        ).pushNamed(AppRoutes.rgbWheel),
                        tooltip: 'Configuració RGB (roda de color)',
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              ClipOval(
                                child: Image.asset(
                                  'assets/imatges/RGB.png',
                                  fit: BoxFit.cover,
                                  width: 56,
                                  height: 56,
                                ),
                              ),
                              const Text(
                                'RGB',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  shadows: [
                                    Shadow(blurRadius: 4, color: Colors.white),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton.extended(
                        heroTag: 'ardmxOneExit',
                        onPressed: () => _exit(ref),
                        icon: const Icon(Icons.logout),
                        label: const Text('Sortir'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
