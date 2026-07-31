import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';
import '../../scene_channels/widgets/nav_arrow_button.dart';

/// Bigger "canals" bar, shared by the ARDMX One screen and ARDMX4's Scene/
/// Channels screen. Two rows: the arrows + "CANALS" title on top, and the 3
/// selected DMX channel numbers (V4-V6) below, each centered directly above
/// its matching slider. ARDMX4's Scene/Channels screen also has a separate
/// scene bar above this one competing for vertical space, so its sliders
/// pass a smaller [ChannelSliders.thumbSize] to make room.
class ChannelNumberBar extends ConsumerWidget {
  const ChannelNumberBar({
    super.key,
    this.fontSize = 34,
    this.padding = const EdgeInsets.fromLTRB(12, 18, 12, 6),
    this.gap = 6,
  });

  /// Font size shared by "CANALS" and the 3 channel numbers below it —
  /// defaults to the original 34; a screen with a separate scene bar above
  /// (e.g. ARDMX4 EVO's Scene/Channels) can pass a smaller value to match
  /// its own "Escena N" text size and free up vertical space.
  final double fontSize;

  /// Outer padding of the whole bar — defaults to the original spacing.
  final EdgeInsetsGeometry padding;

  /// Vertical gap between the "CANALS" row and the channel-numbers row —
  /// defaults to the original 6.
  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ch1 = ref.watch(appStateProvider.select((s) => s.channel1Number));
    final ch2 = ref.watch(appStateProvider.select((s) => s.channel2Number));
    final ch3 = ref.watch(appStateProvider.select((s) => s.channel3Number));
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
    );

    return Container(
      color: Colors.blue.shade900,
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              NavArrowButton(
                icon: Icons.arrow_back,
                onPressed: () =>
                    ref.read(appStateProvider.notifier).advanceChannelGroup(-1),
              ),
              Expanded(
                child: Text(
                  'CANALS',
                  textAlign: TextAlign.center,
                  style: textStyle,
                ),
              ),
              NavArrowButton(
                icon: Icons.arrow_forward,
                onPressed: () =>
                    ref.read(appStateProvider.notifier).advanceChannelGroup(1),
              ),
            ],
          ),
          SizedBox(height: gap),
          // Same horizontal padding as ChannelSliders below, so each number
          // lines up over its slider column.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(child: _ChannelNumber(ch1, style: textStyle)),
                Expanded(child: _ChannelNumber(ch2, style: textStyle)),
                Expanded(child: _ChannelNumber(ch3, style: textStyle)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelNumber extends StatelessWidget {
  const _ChannelNumber(this.number, {required this.style});

  final int? number;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text('${number ?? '—'}', textAlign: TextAlign.center, style: style);
  }
}
