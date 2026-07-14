import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A hue/saturation wheel color picker. Brightness is handled separately by
/// a horizontal slider above this widget on [RgbWheelScreen] — dragging here
/// only ever changes hue and saturation, carrying the existing brightness
/// (the [color] passed in) through untouched. Reports live updates via
/// [onChangedLive] while dragging and a guaranteed final value via
/// [onChangeEnd] on release — mirrors the throttle/commit split used by the
/// channel/volume sliders elsewhere in the app.
class RgbColorWheel extends StatefulWidget {
  const RgbColorWheel({
    super.key,
    required this.color,
    required this.onChangedLive,
    required this.onChangeEnd,
    this.onDragStart,
    this.size = 260,
  });

  final Color color;
  final ValueChanged<Color> onChangedLive;
  final ValueChanged<Color> onChangeEnd;
  final VoidCallback? onDragStart;
  final double size;

  @override
  State<RgbColorWheel> createState() => _RgbColorWheelState();
}

class _RgbColorWheelState extends State<RgbColorWheel> {
  HSVColor? _localHsv;

  HSVColor get _hsv => _localHsv ?? HSVColor.fromColor(widget.color);

  double get _wheelRadius => widget.size / 2 - 16;

  void _updateFromLocalPosition(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final d = localPosition - center;
    final distance = d.distance;

    final angleDeg = (math.atan2(d.dy, d.dx) * 180 / math.pi + 360) % 360;
    final saturation = (distance / _wheelRadius).clamp(0.0, 1.0);
    final next = _hsv.withHue(angleDeg).withSaturation(saturation);

    setState(() => _localHsv = next);
    widget.onChangedLive(next.toColor());
  }

  void _end() {
    widget.onChangeEnd(_hsv.toColor());
    setState(() => _localHsv = null);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (d) {
        widget.onDragStart?.call();
        _updateFromLocalPosition(d.localPosition);
      },
      onPanUpdate: (d) => _updateFromLocalPosition(d.localPosition),
      onPanEnd: (_) => _end(),
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _RgbWheelPainter(hsv: _hsv, wheelRadius: _wheelRadius),
      ),
    );
  }
}

class _RgbWheelPainter extends CustomPainter {
  _RgbWheelPainter({required this.hsv, required this.wheelRadius});

  final HSVColor hsv;
  final double wheelRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Hue/saturation wheel: a full-saturation hue sweep, with a white
    // radial gradient faded on top to desaturate toward the center.
    final wheelRect = Rect.fromCircle(center: center, radius: wheelRadius);
    final huePaint = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFF0000),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF00FFFF),
          Color(0xFF0000FF),
          Color(0xFFFF00FF),
          Color(0xFFFF0000),
        ],
      ).createShader(wheelRect);
    canvas.drawCircle(center, wheelRadius, huePaint);
    final satPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, Colors.white.withValues(alpha: 0)],
      ).createShader(wheelRect);
    canvas.drawCircle(center, wheelRadius, satPaint);

    // Wheel thumb (hue/saturation position).
    final hueRad = hsv.hue * math.pi / 180;
    final thumbR = hsv.saturation * wheelRadius;
    final thumbCenter =
        center + Offset(math.cos(hueRad), math.sin(hueRad)) * thumbR;
    _drawHandle(canvas, thumbCenter, hsv.toColor());
  }

  void _drawHandle(Canvas canvas, Offset pos, Color fill) {
    canvas.drawCircle(pos, 13, Paint()..color = fill);
    canvas.drawCircle(
      pos,
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.black87,
    );
  }

  @override
  bool shouldRepaint(covariant _RgbWheelPainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}
