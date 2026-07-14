import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';
import '../../../widgets/rounded_square_thumb_shape.dart';

/// Debounced volume control (V[16], 0-30). Keeps an ephemeral local value
/// for immediate visual feedback while dragging, sends the real write only
/// after a short pause, and always forces a final send on drag release so
/// the committed value is never lost to a race with the debounce timer.
class VolumeSlider extends ConsumerStatefulWidget {
  const VolumeSlider({super.key});

  @override
  ConsumerState<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends ConsumerState<VolumeSlider> {
  static const _debounceDelay = Duration(milliseconds: 100);

  double? _localValue;
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onChanged(double value) {
    setState(() => _localValue = value);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () => _commit(value));
  }

  void _onChangeEnd(double value) {
    _debounceTimer?.cancel();
    _commit(value);
  }

  void _commit(double value) {
    ref.read(appStateProvider.notifier).setVolume(value.round());
  }

  @override
  Widget build(BuildContext context) {
    final remoteVolume =
        ref.watch(appStateProvider.select((s) => s.volume)) ?? 0;
    final value = (_localValue ?? remoteVolume.toDouble()).clamp(0.0, 30.0);

    return Column(
      children: [
        const Text(
          'Volum',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 10,
            thumbShape: RoundedSquareThumbShape(
              size: 40,
              cornerRadius: 10,
              channelNumber: value.round(),
              textFontSize: 18,
              rotateText: false,
            ),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: 30,
            divisions: 30,
            onChanged: _onChanged,
            onChangeEnd: _onChangeEnd,
          ),
        ),
      ],
    );
  }
}
