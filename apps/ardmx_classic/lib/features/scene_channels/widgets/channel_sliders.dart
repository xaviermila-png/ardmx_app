import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';
import '../../../widgets/rounded_square_thumb_shape.dart';

/// The 3 R/G/B vertical sliders (V1-V3, 0-255), inverted (max at top,
/// matching a physical DMX fader). Writes are throttled (not debounced)
/// while dragging: the Arduino gets a live update roughly every
/// [_throttleInterval] for real-time visual feedback on the actual
/// lights, plus a guaranteed final write on release.
class ChannelSliders extends ConsumerStatefulWidget {
  const ChannelSliders({
    super.key,
    this.valueFontSize = 20,
    this.thumbSize = 56,
    this.cornerRadius = 12,
  });

  /// Font size of the 0-255 value number shown above each slider. Defaults
  /// to the original ARDMX4 Scene/Channels size — callers (e.g. ARDMX One's
  /// screen) can pass a larger value without affecting other screens using
  /// this same widget.
  final double valueFontSize;

  /// Size (width/height) of the square slider thumb. Defaults to the
  /// original size — ARDMX4's Scene/Channels screen passes a smaller value
  /// to leave room for [ChannelNumberBar] above without the track getting
  /// squeezed too short.
  final double thumbSize;

  /// Corner radius of the square slider thumb, scaled down alongside
  /// [thumbSize] so it stays visually proportionate.
  final double cornerRadius;

  @override
  ConsumerState<ChannelSliders> createState() => _ChannelSlidersState();
}

class _ChannelSlidersState extends ConsumerState<ChannelSliders> {
  static const _throttleInterval = Duration(milliseconds: 120);

  double? _local1;
  double? _local2;
  double? _local3;
  Timer? _throttleCooldown;
  bool _pendingDuringCooldown = false;

  @override
  void dispose() {
    _throttleCooldown?.cancel();
    super.dispose();
  }

  void _onChanged(int slot, double value) {
    setState(() => _setLocal(slot, value.roundToDouble()));
    if (_throttleCooldown == null) {
      // Leading edge: send immediately so the very first movement is felt
      // right away, then start a cooldown before the next send is allowed.
      _sendLive();
      _startCooldown();
    } else {
      // Still within the cooldown window — the latest position will go out
      // as soon as it expires (trailing edge), so drag never gets silently
      // dropped even if the finger keeps moving continuously.
      _pendingDuringCooldown = true;
    }
  }

  void _startCooldown() {
    _throttleCooldown = Timer(_throttleInterval, () {
      _throttleCooldown = null;
      if (_pendingDuringCooldown) {
        _pendingDuringCooldown = false;
        _sendLive();
        _startCooldown();
      }
    });
  }

  void _onChangeEnd(int slot, double value) {
    _throttleCooldown?.cancel();
    _throttleCooldown = null;
    _pendingDuringCooldown = false;
    _setLocal(slot, value.roundToDouble());
    _sendLive();
    // Hand display back over to the remote (polled) value now that dragging
    // is over — otherwise this slider would ignore every future update
    // (e.g. the new values that arrive after switching channel group)
    // forever.
    setState(() {
      _local1 = null;
      _local2 = null;
      _local3 = null;
    });
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

  void _sendLive() {
    final state = ref.read(appStateProvider);
    ref
        .read(appStateProvider.notifier)
        .setChannelColors(
          channel1: _local1 ?? state.channel1Value ?? 0,
          channel2: _local2 ?? state.channel2Value ?? 0,
          channel3: _local3 ?? state.channel3Value ?? 0,
        );
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
      margin: const EdgeInsets.symmetric(horizontal: 8),
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
              fontSize: widget.valueFontSize,
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
                    size: widget.thumbSize,
                    cornerRadius: widget.cornerRadius,
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
