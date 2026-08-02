import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/v_map.dart';
import '../../../state/providers.dart';
import '../../../widgets/rounded_square_thumb_shape.dart';

/// Volume control (V[16], 0-30). Writes are throttled (not debounced)
/// while dragging: the Arduino gets a live update roughly every
/// [_throttleInterval] for real-time feedback, plus a guaranteed final
/// write on release.
///
/// Polls V16 itself (not left to whichever screen embeds it): Main Menu has
/// no poll loop of its own at all, so without this the volume shown there
/// could only ever reflect whatever some *other* screen happened to have
/// fetched earlier in the session — e.g. it stayed stale after an ARDMX4
/// config import, even though Cycle Programming (which does poll V16
/// itself) picked up the new value fine.
class VolumeSlider extends ConsumerStatefulWidget {
  const VolumeSlider({
    super.key,
    this.leading,
    this.leadingAlignment = Alignment.centerLeft,
    this.titleFontSize = 20,
    this.titleAlignment = Alignment.center,
    this.titleRowHeight = 28,
    this.thumbSize = 40,
  });

  /// Optional widget shown at the far left, overlapping the same row as
  /// the "Volum" title — used by Cycle Programming to show the selected
  /// song number at the same height as "Volum".
  final Widget? leading;

  /// Where [leading] sits within its row — defaults to the original
  /// centered-vertically left placement.
  final Alignment leadingAlignment;

  /// Font size of the "Volum" title (and, by convention, whatever [leading]
  /// widget the caller builds at a matching size) — defaults to the
  /// original 20 so every existing caller is unaffected; a screen tight on
  /// vertical space (e.g. a 4-scene Cycle Programming layout that would
  /// otherwise paginate) can pass a smaller value.
  final double titleFontSize;

  /// Where the "Volum" title sits within its row — defaults to centered
  /// (unaffected for existing callers). [Alignment.centerRight] frees up
  /// the row for [leading] to read as a compact single line instead of two
  /// overlapping centered/left labels.
  final Alignment titleAlignment;

  /// Height of the row containing the title (and [leading]) — defaults to
  /// the original 28.
  final double titleRowHeight;

  /// Side length of the square slider thumb (which also shows the current
  /// volume number) — defaults to the original 40.
  final double thumbSize;

  @override
  ConsumerState<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends ConsumerState<VolumeSlider> {
  static const _throttleInterval = Duration(milliseconds: 120);
  static const _pollInterval = Duration(milliseconds: 800);

  double? _localValue;
  Timer? _throttleCooldown;
  bool _pendingDuringCooldown = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Deferred a frame: _poll() calls ModalRoute.of(context), not
    // resolvable synchronously inside initState (same fix as every other
    // polling screen/widget in the app).
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  void _poll() {
    // Only the topmost route should poll — same reasoning as every other
    // screen's _poll(): two screens (or, here, two mounted-but-covered
    // instances of this same widget) polling at once can corrupt the wire
    // protocol.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    ref.read(protocolProvider).requestV(VIndex.volume);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
    // Hand display back over to the remote (polled) value now that dragging
    // is over — otherwise this slider would ignore every future update
    // (e.g. a value applied via config import) forever, stuck showing
    // whatever was last dragged to. Same fix already applied to
    // ChannelSliders' own _onChangeEnd for the identical reason.
    setState(() => _localValue = null);
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
        SizedBox(
          height: widget.titleRowHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: widget.titleAlignment,
                child: Text(
                  'Volum',
                  style: TextStyle(
                    fontSize: widget.titleFontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (widget.leading != null)
                Align(alignment: widget.leadingAlignment, child: widget.leading),
            ],
          ),
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 10,
            thumbShape: RoundedSquareThumbShape(
              size: widget.thumbSize,
              cornerRadius: 10,
              channelNumber: value.round(),
              textFontSize: widget.thumbSize * 0.45,
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
            semanticFormatterCallback: (v) => 'Volum, ${v.round()} de 30',
          ),
        ),
      ],
    );
  }
}
