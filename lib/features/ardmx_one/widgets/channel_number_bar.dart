import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';
import '../../scene_channels/widgets/nav_arrow_button.dart';

/// Bigger "canals" bar for the ARDMX One screen. Two rows: the arrows +
/// "CANALS" title on top, and the 3 selected DMX channel numbers (V4-V6)
/// below, each centered directly above its matching slider — unlike
/// ARDMX4's plain "CANALS"-only bar (which deliberately doesn't show
/// numbers, per an earlier explicit user decision for that screen), this
/// screen has no separate scene bar competing for space, so it fits both.
class ChannelNumberBar extends ConsumerWidget {
  const ChannelNumberBar({super.key});

  static const _textStyle = TextStyle(
    color: Colors.white,
    fontSize: 34,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ch1 = ref.watch(appStateProvider.select((s) => s.channel1Number));
    final ch2 = ref.watch(appStateProvider.select((s) => s.channel2Number));
    final ch3 = ref.watch(appStateProvider.select((s) => s.channel3Number));

    return Container(
      color: Colors.blue.shade900,
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
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
              const Expanded(
                child: Text(
                  'CANALS',
                  textAlign: TextAlign.center,
                  style: _textStyle,
                ),
              ),
              NavArrowButton(
                icon: Icons.arrow_forward,
                onPressed: () =>
                    ref.read(appStateProvider.notifier).advanceChannelGroup(1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Same horizontal padding as ChannelSliders below, so each number
          // lines up over its slider column.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(child: _ChannelNumber(ch1)),
                Expanded(child: _ChannelNumber(ch2)),
                Expanded(child: _ChannelNumber(ch3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelNumber extends StatelessWidget {
  const _ChannelNumber(this.number);

  final int? number;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${number ?? '—'}',
      textAlign: TextAlign.center,
      style: ChannelNumberBar._textStyle,
    );
  }
}
