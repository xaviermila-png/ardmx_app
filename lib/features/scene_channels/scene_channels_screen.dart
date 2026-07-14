import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import 'widgets/channel_group_navigator.dart';
import 'widgets/channel_sliders.dart';
import 'widgets/scene_navigator.dart';
import 'widgets/transition_mode_selector.dart';

class SceneChannelsScreen extends ConsumerStatefulWidget {
  const SceneChannelsScreen({super.key});

  @override
  ConsumerState<SceneChannelsScreen> createState() =>
      _SceneChannelsScreenState();
}

class _SceneChannelsScreenState extends ConsumerState<SceneChannelsScreen> {
  // 400ms keeps the round trip (10-index batch over 9600 baud SPP,
  // ~150-250ms in practice) comfortably ahead of the next poll while
  // noticeably shortening the visible lag after changing scene/channel
  // group compared to the original 1s interval.
  static const _pollInterval = Duration(milliseconds: 400);

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Everything this screen shows (scene number, channel numbers, channel
    // values, transition modes) must be explicitly requested — the
    // Virtuino wire protocol never pushes V-values unsolicited. Polling
    // repeatedly (not just once) matches CycleProgressBar's proven-working
    // pattern: a single one-shot request can be lost to a transient race
    // and never retried, leaving the screen stuck showing nothing.
    _poll();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _poll() {
    // Root cause of the earlier "nothing shows up" bug was NOT UART
    // timing/batching — it was that single-digit V-indices (V0-V9) never
    // get a reply from the Arduino/VirtuinoCM library unless zero-padded to
    // 2 digits. That's now fixed centrally in VirtuinoProtocol's _pad(), so
    // it's safe to batch all the indices this screen needs into one send
    // again.
    ref.read(protocolProvider).requestAll([
      VIndex.activeScene,
      VIndex.channel1Number,
      VIndex.channel2Number,
      VIndex.channel3Number,
      VIndex.channel1Value,
      VIndex.channel2Value,
      VIndex.channel3Value,
      VIndex.transitionModeChannel1,
      VIndex.transitionModeChannel2,
      VIndex.transitionModeChannel3,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Escena / Canals',
      // Navigation lives entirely in the bottom row below (back + RGB
      // wheel) instead of the default AppBar chevron, so there's a single,
      // consistent way to move between screens.
      automaticallyImplyLeading: false,
      body: Column(
        children: [
          const SceneNavigator(),
          const ChannelGroupNavigator(),
          // A bit of breathing room below the blue channels box, made
          // possible by the transition-mode selector below being more
          // compact now than the sliders shrinking to fit.
          const SizedBox(height: 14),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: ChannelSliders(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: TransitionModeSelector(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FloatingActionButton(
                  heroTag: 'sceneChannelsBack',
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Tornar al menú principal',
                  child: const Icon(Icons.arrow_back),
                ),
                FloatingActionButton(
                  heroTag: 'sceneChannelsRgbWheel',
                  backgroundColor: Colors.deepOrange,
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.rgbWheel),
                  tooltip: 'Configuració RGB (roda de color)',
                  child: const Icon(Icons.color_lens, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
