import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';
import 'rounded_square_thumb_shape.dart';

/// The 3 R/G/B vertical sliders (V1-V3, 0-255), inverted (max at top,
/// matching a physical DMX fader). Same debounce pattern as
/// [VolumeSlider]: ephemeral local value while dragging for immediate
/// visual feedback, committed 100ms after the user pauses, and always
/// force-committed on drag release.
class ChannelSliders extends ConsumerStatefulWidget {
  const ChannelSliders({super.key});

  @override
  ConsumerState<ChannelSliders> createState() => _ChannelSlidersState();
}

class _ChannelSlidersState extends ConsumerState<ChannelSliders> {
  static const _debounceDelay = Duration(milliseconds: 100);

  double? _local1;
  double? _local2;
  double? _local3;
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onChanged(int slot, double value) {
    setState(() => _setLocal(slot, value.roundToDouble()));
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, _commit);
  }

  void _onChangeEnd(int slot, double value) {
    _debounceTimer?.cancel();
    _setLocal(slot, value.roundToDouble());
    _commit();
  }

  void _setLocal(int slot, double value) {
    switch (slot) {
      case 1:
        _local1 = value;
      case 2:
        _local2 = value;
      case 3:
        _local3 = value;
    }
  }

  void _commit() {
    final state = ref.read(appStateProvider);
    ref
        .read(appStateProvider.notifier)
        .setChannelColors(
          channel1: _local1 ?? state.channel1Value ?? 0,
          channel2: _local2 ?? state.channel2Value ?? 0,
          channel3: _local3 ?? state.channel3Value ?? 0,
        );
    // Hand display back over to the remote (polled) value once we've sent
    // ours — otherwise this slider would ignore every future update (e.g.
    // the new values that arrive after switching channel group) forever.
    setState(() {
      _local1 = null;
      _local2 = null;
      _local3 = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final remote1 =
        ref.watch(appStateProvider.select((s) => s.channel1Value)) ?? 0;
    final remote2 =
        ref.watch(appStateProvider.select((s) => s.channel2Value)) ?? 0;
    final remote3 =
        ref.watch(appStateProvider.select((s) => s.channel3Value)) ?? 0;

    final ch1 = ref.watch(appStateProvider.select((s) => s.channel1Number));
    final ch2 = ref.watch(appStateProvider.select((s) => s.channel2Number));
    final ch3 = ref.watch(appStateProvider.select((s) => s.channel3Number));

    final v1 = (_local1 ?? remote1).clamp(0.0, 255.0);
    final v2 = (_local2 ?? remote2).clamp(0.0, 255.0);
    final v3 = (_local3 ?? remote3).clamp(0.0, 255.0);

    return Row(
      children: [
        Expanded(child: _slider(1, v1, ch1, Colors.red)),
        Expanded(child: _slider(2, v2, ch2, Colors.green)),
        Expanded(child: _slider(3, v3, ch3, Colors.blue)),
      ],
    );
  }

  Widget _slider(int slot, double value, int? channelNumber, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value.round().toString(),
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 10,
                  thumbShape: RoundedSquareThumbShape(
                    size: 56,
                    cornerRadius: 12,
                    channelNumber: channelNumber,
                    textColor: color,
                  ),
                ).copyWith(activeTrackColor: color),
                child: Slider(
                  value: value,
                  min: 0,
                  max: 255,
                  onChanged: (v) => _onChanged(slot, v),
                  onChangeEnd: (v) => _onChangeEnd(slot, v),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
