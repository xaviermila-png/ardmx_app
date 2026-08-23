import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import '../ardmx_one/widgets/channel_name_row.dart';
import '../ardmx_one/widgets/channel_number_bar.dart';
import '../scene_channels/widgets/channel_sliders.dart';
import '../scene_channels/widgets/channel_transition_editor.dart';
import '../scene_channels/widgets/rgb_wheel_button.dart';
import '../scene_channels/widgets/scene_navigator.dart';

/// Scene/Channels screen for the ARDMX EVO tree — same V1-V9/V71 protocol
/// as the Mega's own [SceneChannelsScreen], plus [ChannelNameRow] (V65-V67,
/// which the Mega doesn't have but ARDMX One and EVO both do) and
/// [ChannelTransitionEditor] (V71, each channel's own 4 transitions —
/// replaces the old per-channel V31-V33 `TransitionModeSelector`).
class ArdmxEvoSceneChannelsScreen extends ConsumerStatefulWidget {
  const ArdmxEvoSceneChannelsScreen({super.key});

  @override
  ConsumerState<ArdmxEvoSceneChannelsScreen> createState() =>
      _ArdmxEvoSceneChannelsScreenState();
}

class _ArdmxEvoSceneChannelsScreenState
    extends ConsumerState<ArdmxEvoSceneChannelsScreen> {
  static const _pollInterval = Duration(milliseconds: 400);

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
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

    ref.read(protocolProvider).requestAll([
      VIndex.activeScene,
      VIndex.channel1Number,
      VIndex.channel2Number,
      VIndex.channel3Number,
      VIndex.channel1Value,
      VIndex.channel2Value,
      VIndex.channel3Value,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Escena / Canals',
      onBack: () => Navigator.of(context).pop(),
      // The nav bars up top stay pinned; only the sliders+transition editor
      // below scroll. Letting the Scaffold resize (default, no override
      // here any more) shrinks the Expanded scroll area when the keyboard
      // opens — ChannelSliders now has a FIXED height (not Expanded) inside
      // that scroll area, so when the shrunk area can't fit everything
      // (editing the %salt field low down), it scrolls the focused field
      // into view instead of overflowing (confirmed on real hardware: the
      // old Expanded-fills-everything version overflowed by a few px under
      // the keyboard, since Expanded can't ask a Slider to render smaller
      // than its own minimum).
      body: Column(
        children: [
          const SceneNavigator(),
          const ChannelNumberBar(
            fontSize: 24,
            padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
            gap: 3,
          ),
          const ChannelNameRow(),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(
                    height: 240,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: ChannelSliders(thumbSize: 48, cornerRadius: 10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                    child: ChannelTransitionEditor(
                      // Sits alongside the "Transició Escena N → Escena M"
                      // title instead of its own row underneath — that
                      // dedicated FAB row took ~80px the sliders above
                      // needed more (they were visibly getting squeezed).
                      trailing: RgbWheelButton(
                        heroTag: 'ardmxEvoSceneChannelsRgbWheel',
                        onPressed: () => Navigator.of(
                          context,
                        ).pushNamed(AppRoutes.rgbWheel),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
