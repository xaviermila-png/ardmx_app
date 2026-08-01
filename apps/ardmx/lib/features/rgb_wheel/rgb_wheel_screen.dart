import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/rounded_square_thumb_shape.dart';
import 'widgets/rgb_color_wheel.dart';

/// RGB colour picker for the 3 active channels (V1-V3), replacing the
/// Virtuino color-wheel screen. Shows the same channel numbers (V4-V6) and
/// live values (V1-V3) as the Scene/Channels screen, since they're the same
/// underlying variables — this is just an alternate (hue/saturation wheel +
/// a horizontal brightness slider) way of setting them.
class RgbWheelScreen extends ConsumerStatefulWidget {
  const RgbWheelScreen({super.key});

  @override
  ConsumerState<RgbWheelScreen> createState() => _RgbWheelScreenState();
}

class _RgbWheelScreenState extends ConsumerState<RgbWheelScreen> {
  static const _pollInterval = Duration(milliseconds: 400);
  // Slowed from 120ms to ~4 writes/second: even with polling paused during
  // a drag (see _poll() below), sending this screen's writes faster than
  // that was still enough to occasionally corrupt the Arduino's channel
  // state on real hardware.
  static const _throttleInterval = Duration(milliseconds: 250);

  Timer? _pollTimer;
  Color? _localColor;

  // While actively dragging (wheel or brightness slider), the poll timer is
  // paused — see _poll() below for why.
  bool _dragging = false;
  Timer? _throttleCooldown;
  bool _pendingDuringCooldown = false;
  Color? _pendingColor;

  @override
  void initState() {
    super.initState();
    // Same "the Arduino never pushes V-values unsolicited" pattern used by
    // Scene/Channels — poll continuously so numbers/values are always live.
    // The first call is deferred a frame since _poll() calls
    // ModalRoute.of(context), which isn't resolvable synchronously inside
    // initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _throttleCooldown?.cancel();
    super.dispose();
  }

  void _poll() {
    // Same guard as Scene/Channels: this screen's poll timer should only
    // fire while its route is actually the topmost one, or two screens'
    // "!Vxx=?$" requests can interleave into corrupted frames on the wire.
    // Also paused while actively dragging (wheel or brightness slider): a
    // poll request landing in between two live-drag writes was previously
    // enough to corrupt the wire protocol badly enough to leave garbage
    // permanently stuck in the Arduino's channel-number variables, so drag
    // writes and polls are kept mutually exclusive in time.
    if (_dragging) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;

    ref.read(protocolProvider).requestAll([
      VIndex.channel1Number,
      VIndex.channel2Number,
      VIndex.channel3Number,
      VIndex.channel1Value,
      VIndex.channel2Value,
      VIndex.channel3Value,
    ]);
  }

  void _onDragStart() {
    _dragging = true;
  }

  // Leading+trailing throttle, same pattern as ChannelSliders/VolumeSlider:
  // send immediately on the first movement, then at most once per
  // [_throttleInterval] while the drag continues, for live hardware
  // feedback. Shared between the wheel and the brightness slider since both
  // ultimately just produce a new Color to commit.
  void _liveUpdate(Color color) {
    setState(() => _localColor = color);
    _pendingColor = color;
    if (_throttleCooldown == null) {
      _send(color);
      _startCooldown();
    } else {
      _pendingDuringCooldown = true;
    }
  }

  void _startCooldown() {
    _throttleCooldown = Timer(_throttleInterval, () {
      _throttleCooldown = null;
      if (_pendingDuringCooldown) {
        _pendingDuringCooldown = false;
        _send(_pendingColor!);
        _startCooldown();
      }
    });
  }

  void _onLive(Color color) => _liveUpdate(color);

  void _onEnd(Color color) {
    _throttleCooldown?.cancel();
    _throttleCooldown = null;
    _pendingDuringCooldown = false;
    _send(color);
    // Hand display back to the remote (polled) value now that dragging is
    // over — otherwise the wheel would ignore future external updates.
    setState(() => _localColor = null);
    _dragging = false;
  }

  // Brightness slider only ever changes value (via withValue), keeping the
  // hue/saturation the wheel last set untouched.
  Color _currentColor() {
    if (_localColor != null) return _localColor!;
    final s = ref.read(appStateProvider);
    return Color.fromARGB(
      255,
      (s.channel1Value ?? 0).round().clamp(0, 255),
      (s.channel2Value ?? 0).round().clamp(0, 255),
      (s.channel3Value ?? 0).round().clamp(0, 255),
    );
  }

  void _onBrightnessLive(double value255) {
    final next = HSVColor.fromColor(
      _currentColor(),
    ).withValue((value255 / 255).clamp(0.0, 1.0));
    _liveUpdate(next.toColor());
  }

  void _onBrightnessEnd(double value255) {
    final next = HSVColor.fromColor(
      _currentColor(),
    ).withValue((value255 / 255).clamp(0.0, 1.0));
    _onEnd(next.toColor());
  }

  void _send(Color color) {
    ref
        .read(appStateProvider.notifier)
        .setChannelColors(
          channel1: (color.r * 255).roundToDouble(),
          channel2: (color.g * 255).roundToDouble(),
          channel3: (color.b * 255).roundToDouble(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final ch1 = ref.watch(appStateProvider.select((s) => s.channel1Number));
    final ch2 = ref.watch(appStateProvider.select((s) => s.channel2Number));
    final ch3 = ref.watch(appStateProvider.select((s) => s.channel3Number));
    final v1 = ref.watch(appStateProvider.select((s) => s.channel1Value)) ?? 0;
    final v2 = ref.watch(appStateProvider.select((s) => s.channel2Value)) ?? 0;
    final v3 = ref.watch(appStateProvider.select((s) => s.channel3Value)) ?? 0;

    final remoteColor = Color.fromARGB(
      255,
      v1.round().clamp(0, 255),
      v2.round().clamp(0, 255),
      v3.round().clamp(0, 255),
    );
    final displayColor = _localColor ?? remoteColor;
    final brightness255 =
        (HSVColor.fromColor(displayColor).value * 255).clamp(0.0, 255.0);

    return AppScaffold(
      title: 'Configuració RGB',
      automaticallyImplyLeading: false,
      body: Column(
        children: [
          const SizedBox(height: 8),
          const Text(
            'Canals',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text('${ch1 ?? '—'}', style: _numberStyle),
              Text('${ch2 ?? '—'}', style: _numberStyle),
              Text('${ch3 ?? '—'}', style: _numberStyle),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            color: Colors.grey.shade300,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(
                  '${(displayColor.r * 255).round()}',
                  style: _valueStyle(Colors.red),
                ),
                Text(
                  '${(displayColor.g * 255).round()}',
                  style: _valueStyle(Colors.green),
                ),
                Text(
                  '${(displayColor.b * 255).round()}',
                  style: _valueStyle(Colors.blue),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wheelSize =
                      constraints.maxWidth < constraints.maxHeight
                      ? constraints.maxWidth * 0.95
                      : constraints.maxHeight * 0.95;
                  return RgbColorWheel(
                    size: wheelSize,
                    color: displayColor,
                    onChangedLive: _onLive,
                    onChangeEnd: _onEnd,
                    onDragStart: _onDragStart,
                  );
                },
              ),
            ),
          ),
          const Text(
            'Intensitat',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 10,
              activeTrackColor: Colors.amber.shade700,
              inactiveTrackColor: Colors.amber.shade100,
              thumbShape: RoundedSquareThumbShape(
                size: 40,
                cornerRadius: 10,
                channelNumber: brightness255.round(),
                textColor: Colors.amber.shade900,
                textFontSize: 16,
                rotateText: false,
              ),
            ),
            child: Slider(
              value: brightness255,
              min: 0,
              max: 255,
              divisions: 255,
              onChangeStart: (_) => _onDragStart(),
              onChanged: _onBrightnessLive,
              onChangeEnd: _onBrightnessEnd,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                FloatingActionButton(
                  heroTag: 'rgbWheelBack',
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Tornar a Escena/Canals',
                  child: const Icon(Icons.arrow_back),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _numberStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);

  static TextStyle _valueStyle(Color color) => TextStyle(
    color: color,
    fontSize: 24,
    fontWeight: FontWeight.bold,
  );
}
