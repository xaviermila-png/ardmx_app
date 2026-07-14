import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';
import '../../../widgets/rounded_square_thumb_shape.dart';

/// Volume control (V[16], 0-30). Writes are throttled (not debounced)
/// while dragging: the Arduino gets a live update roughly every
/// [_throttleInterval] for real-time feedback, plus a guaranteed final
/// write on release.
class VolumeSlider extends ConsumerStatefulWidget {
  const VolumeSlider({super.key});

  @override
  ConsumerState<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends ConsumerState<VolumeSlider> {
  static const _throttleInterval = Duration(milliseconds: 120);

  double? _localValue;
  Timer? _throttleCooldown;
  bool _pendingDuringCooldown = false;

  @override
  void dispose() {
    _throttleCooldown?.cancel();
    super.dispose();
  }

  void _onChanged(double value) {
    setState(() => _localValue = value);
    if (_throttleCooldown == null) {
      // Leading edge: send immediately, then start a cooldown before the
      // next send is allowed.
      _sendLive(value);
      _startCooldown();
    } else {
      // Trailing edge: the latest position goes out as soon as the
      // cooldown expires, so a continuous drag is never silently dropped.
      _pendingDuringCooldown = true;
    }
  }

  void _startCooldown() {
    _throttleCooldown = Timer(_throttleInterval, () {
      _throttleCooldown = null;
      if (_pendingDuringCooldown) {
        _pendingDuringCooldown = false;
        _sendLive(_localValue!);
        _startCooldown();
      }
    });
  }

  void _onChangeEnd(double value) {
    _throttleCooldown?.cancel();
    _throttleCooldown = null;
    _pendingDuringCooldown = false;
    _sendLive(value);
  }

  void _sendLive(double value) {
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
