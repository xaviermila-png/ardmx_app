import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/v_map.dart';
import '../../../state/providers.dart';

/// "Tipus de transició a l'escena" — 3 columns (one per R/G/B channel) of
/// Gradual/Inicial/Final radio options, writing V31-V33 as a single
/// batched write via [AppStateNotifier.setTransitionModes].
class TransitionModeSelector extends ConsumerWidget {
  const TransitionModeSelector({super.key});

  static TransitionMode? _fromValue(int? value) {
    if (value == null) return null;
    for (final mode in TransitionMode.values) {
      if (mode.vValue == value) return mode;
    }
    return null;
  }

  static String _label(TransitionMode mode) {
    switch (mode) {
      case TransitionMode.gradual:
        return 'Gradual';
      case TransitionMode.initial:
        return 'Inicial';
      case TransitionMode.finalMode:
        return 'Final';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode1 = _fromValue(
      ref.watch(appStateProvider.select((s) => s.transitionModeChannel1)),
    );
    final mode2 = _fromValue(
      ref.watch(appStateProvider.select((s) => s.transitionModeChannel2)),
    );
    final mode3 = _fromValue(
      ref.watch(appStateProvider.select((s) => s.transitionModeChannel3)),
    );

    void update(int channel, TransitionMode mode) {
      final s = ref.read(appStateProvider);
      final c1 = _fromValue(s.transitionModeChannel1) ?? TransitionMode.gradual;
      final c2 = _fromValue(s.transitionModeChannel2) ?? TransitionMode.gradual;
      final c3 = _fromValue(s.transitionModeChannel3) ?? TransitionMode.gradual;
      ref
          .read(appStateProvider.notifier)
          .setTransitionModes(
            channel1: channel == 1 ? mode : c1,
            channel2: channel == 2 ? mode : c2,
            channel3: channel == 3 ? mode : c3,
          );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "Tipus de transició a l'escena",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: _ModeColumn(
                current: mode1,
                color: Colors.red,
                channelName: 'vermell',
                onChanged: (m) => update(1, m),
              ),
            ),
            Expanded(
              child: _ModeColumn(
                current: mode2,
                color: Colors.green,
                channelName: 'verd',
                onChanged: (m) => update(2, m),
              ),
            ),
            Expanded(
              child: _ModeColumn(
                current: mode3,
                color: Colors.blue,
                channelName: 'blau',
                onChanged: (m) => update(3, m),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One channel's Gradual/Inicial/Final picker — a compact, boxed control
/// (same bordered look as each channel's slider) with a rounded-square
/// checkmark indicator instead of Material's default round radio dot, so
/// the whole selector reads as one unit tied to its slider above.
class _ModeColumn extends StatelessWidget {
  const _ModeColumn({
    required this.current,
    required this.color,
    required this.channelName,
    required this.onChanged,
  });

  final TransitionMode? current;
  final Color color;
  final String channelName;
  final ValueChanged<TransitionMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final mode in TransitionMode.values)
            _ModeOption(
              label: TransitionModeSelector._label(mode),
              color: color,
              channelName: channelName,
              selected: current == mode,
              onTap: () => onChanged(mode),
            ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.label,
    required this.color,
    required this.channelName,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final String channelName;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // inMutuallyExclusiveGroup: the 3 options within one channel's
      // column are a radio group (Gradual/Inicial/Final), not independent
      // toggles — this tells a screen reader that too.
      label: 'Transició $label, canal $channelName',
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        // 48dp minimum touch target (WCAG 2.5.5/2.5.8) — the visible 20x20
        // checkbox + text is much shorter than that on its own, so this pads
        // the tappable area out to the full height without changing what's
        // drawn.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: color, width: 2),
                      color: selected ? color : Colors.transparent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(label, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
