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

  final _textController1 = TextEditingController();
  final _textController2 = TextEditingController();
  final _textController3 = TextEditingController();
  final _focusNode1 = FocusNode();
  final _focusNode2 = FocusNode();
  final _focusNode3 = FocusNode();

  @override
  void dispose() {
    _throttleCooldown?.cancel();
    _textController1.dispose();
    _textController2.dispose();
    _textController3.dispose();
    _focusNode1.dispose();
    _focusNode2.dispose();
    _focusNode3.dispose();
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

  /// Commits whatever's typed in the numeric field for [slot] — clamped
  /// (not rejected) to 0-255, same tolerance as dragging the slider past
  /// its own track. Mirrors [_onChangeEnd]'s exact call sequence so the
  /// field and slider always agree afterward and both hand display back to
  /// the polled remote value once the write is sent.
  void _commitText(int slot) {
    final controller = switch (slot) {
      1 => _textController1,
      2 => _textController2,
      _ => _textController3,
    };
    final parsed = int.tryParse(controller.text);
    if (parsed == null) return;
    _onChangeEnd(slot, parsed.clamp(0, 255).toDouble());
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

    // Keep the numeric field in sync with the slider — but only while the
    // user isn't actively typing in it, same guard as ChannelNameRow's
    // equivalent text field, so a live poll reply never overwrites what
    // they're mid-way through entering.
    if (!_focusNode1.hasFocus) _textController1.text = v1.round().toString();
    if (!_focusNode2.hasFocus) _textController2.text = v2.round().toString();
    if (!_focusNode3.hasFocus) _textController3.text = v3.round().toString();

    return Row(
      children: [
        Expanded(
          child: _slider(1, v1, ch1, Colors.red, _textController1, _focusNode1),
        ),
        Expanded(
          child: _slider(
            2,
            v2,
            ch2,
            Colors.green,
            _textController2,
            _focusNode2,
          ),
        ),
        Expanded(
          child: _slider(3, v3, ch3, Colors.blue, _textController3, _focusNode3),
        ),
      ],
    );
  }

  Widget _slider(
    int slot,
    double value,
    int? channelNumber,
    Color color,
    TextEditingController textController,
    FocusNode focusNode,
  ) {
    // The channel color is carried by the border and the slider track —
    // it's deliberately not used for the value/channel-number *text*
    // (Colors.red/green especially fell as low as ~2.5:1 against a light
    // background, well under WCAG's 3:1 large-text minimum). Neutral
    // onSurface text keeps guaranteed contrast regardless of which
    // channel color is in play.
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final channelLabel = channelNumber != null
        ? 'Fader canal $slot, canal $channelNumber'
        : 'Fader canal $slot';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          SizedBox(
            // 3 digits ("255") at a bold fontSize needs noticeably more
            // room than a plain Text of the same size did — a TextField
            // has its own internal caret/hit-test padding on top of the
            // glyphs. Confirmed too narrow (digits clipped/overlapping) on
            // real hardware at the old 2.2x multiplier.
            width: (widget.valueFontSize * 3.4).clamp(56.0, 120.0),
            child: TextField(
              controller: textController,
              focusNode: focusNode,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 3,
              style: TextStyle(
                color: onSurface,
                fontSize: widget.valueFontSize,
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(
                counterText: '',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 2),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _commitText(slot),
              onTapOutside: (_) {
                FocusManager.instance.primaryFocus?.unfocus();
                _commitText(slot);
              },
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
                    textColor: onSurface,
                  ),
                ).copyWith(activeTrackColor: color),
                child: Slider(
                  value: value,
                  min: 0,
                  max: 255,
                  onChanged: (v) => _onChanged(slot, v),
                  onChangeEnd: (v) => _onChangeEnd(slot, v),
                  // Custom announcement (e.g. "Fader canal 1, canal 4, 180")
                  // instead of Slider's own generic "value" — this keeps
                  // its built-in adjustable semantics (swipe up/down to
                  // change value with a screen reader) intact, unlike
                  // wrapping it in a Semantics/ExcludeSemantics pair which
                  // would silently drop that interaction.
                  semanticFormatterCallback: (v) =>
                      '$channelLabel, ${v.round()} de 255',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
