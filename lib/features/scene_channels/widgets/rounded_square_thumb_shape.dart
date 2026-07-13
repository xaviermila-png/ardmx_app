import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A rounded-square [Slider] thumb (gray outline, very light gray fill)
/// instead of Material's default filled circle — the fader's colored track
/// already conveys the channel, so the thumb stays neutral. Optionally
/// shows the DMX channel number centered inside it.
class RoundedSquareThumbShape extends SliderComponentShape {
  const RoundedSquareThumbShape({
    this.size = 48,
    this.cornerRadius = 10,
    this.channelNumber,
    this.textColor = Colors.black,
  });

  final double size;
  final double cornerRadius;
  final int? channelNumber;
  final Color textColor;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: size, height: size),
      Radius.circular(cornerRadius),
    );
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFFEEEEEE));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.grey.shade600
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    if (channelNumber == null) return;
    // This thumb is painted inside the Slider's own RotatedBox(quarterTurns:
    // 3) ancestor, so without a counter-rotation the number would render
    // sideways — rotate the opposite way here so it reads upright.
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$channelNumber',
        style: TextStyle(
          color: textColor,
          fontSize: 19,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(math.pi / 2);
    canvas.translate(-center.dx, -center.dy);
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
    canvas.restore();
  }
}
