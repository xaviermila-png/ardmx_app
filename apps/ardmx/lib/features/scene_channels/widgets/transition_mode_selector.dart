import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/v_map.dart';
import '../../../state/providers.dart';

/// "Tipus de transició a l'escena" — 3 columns (one per R/G/B channel,
/// lined up under that channel's slider above), each a compact vertical
/// [ToggleButtons] of Gradual/Inicial/Final, writing V31-V33 as a single
/// batched write via [AppStateNotifier.setTransitionModes].
///
/// A horizontal `SegmentedButton` per channel (one earlier design of this
/// widget) took up enough height stacked 3-high to squeeze the sliders
/// above down to an uncomfortable size — this stays in the original
/// side-by-side 3-column layout instead, just with [ToggleButtons] standing
/// in for the old raw checkbox rows.
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

    return Row(
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
    );
  }
}

/// One channel's Gradual/Inicial/Final picker — a small vertical
/// [ToggleButtons] tinted with that channel's color, inside the same
/// bordered box the old checkbox column used.
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
    final selected = current ?? TransitionMode.gradual;
    return Semantics(
      // Groups the 3 toggles under one accessible description of which
      // channel this column controls — each toggle's own label/selected
      // state still comes from ToggleButtons itself.
      label: 'Transició, canal $channelName',
      container: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: ToggleButtons(
            direction: Axis.vertical,
            constraints: const BoxConstraints(minHeight: 26, minWidth: 64),
            borderRadius: BorderRadius.circular(6),
            fillColor: color,
            // Black rather than white: white text on the channel colors
            // (especially green/blue) fell as low as ~2.8:1 against WCAG's
            // 4.5:1 minimum for normal-sized text; black clears it
            // comfortably (5.7-7.6:1) without changing any brand color.
            selectedColor: Colors.black,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            isSelected: [
              for (final mode in TransitionMode.values) mode == selected,
            ],
            onPressed: (index) => onChanged(TransitionMode.values[index]),
            children: [
              for (final mode in TransitionMode.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    TransitionModeSelector._label(mode),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
