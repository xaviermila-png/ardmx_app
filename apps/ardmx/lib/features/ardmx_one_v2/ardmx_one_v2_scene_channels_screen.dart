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
import '../scene_channels/widgets/global_transition_editor.dart';
import '../scene_channels/widgets/scene_navigator.dart';

/// Scene/Channels screen for the ARDMX One v2 tree — same composition as
/// the ARDMX EVO tree's own [ArdmxEvoSceneChannelsScreen] (V1-V9/V71/V72),
/// reusing every widget verbatim since the underlying protocol is
/// identical by design (see ardmx-one-firmware/src/main.cpp).
class ArdmxOneV2SceneChannelsScreen extends ConsumerStatefulWidget {
  const ArdmxOneV2SceneChannelsScreen({super.key});

  @override
  ConsumerState<ArdmxOneV2SceneChannelsScreen> createState() =>
      _ArdmxOneV2SceneChannelsScreenState();
}

class _ArdmxOneV2SceneChannelsScreenState
    extends ConsumerState<ArdmxOneV2SceneChannelsScreen> {
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
      // Mateix motiu que a l'EVO: el teclat en editar un nom de canal no té
      // marge per encongir els sliders de sota sense trencar el layout.
      resizeToAvoidBottomInset: false,
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
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: ChannelSliders(thumbSize: 48, cornerRadius: 10),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: GlobalTransitionEditor(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: 'ardmxOneV2SceneChannelsRgbWheel',
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.rgbWheel),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
