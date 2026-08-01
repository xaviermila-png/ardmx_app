import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A rounded-square [Slider] thumb (gray outline, very light gray fill)
/// instead of Material's default filled circle. Optionally shows a number
/// (e.g. a DMX channel number) centered inside it — pass `null` for a plain
/// neutral thumb (e.g. the Main Menu volume slider).
class RoundedSquareThumbShape extends SliderComponentShape {
  const RoundedSquareThumbShape({
    this.size = 48,
    this.cornerRadius = 10,
    this.channelNumber,
    this.textColor = Colors.black,
    this.textFontSize = 19,
    this.rotateText = true,
  });

  final double size;
  final double cornerRadius;
  final int? channelNumber;
  final Color textColor;
  final double textFontSize;
  // Callers that rotate the Slider itself (e.g. the DMX channel faders,
  // wrapped in RotatedBox(quarterTurns: 3)) need this text counter-rotated
  // or it renders sideways — see ChannelSliders. Non-rotated sliders (e.g.
  // the Main Menu volume slider) should pass false.
  final bool rotateText;

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
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$channelNumber',
        style: TextStyle(
          color: textColor,
          fontSize: textFontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    if (!rotateText) {
      textPainter.paint(
        canvas,
        center - Offset(textPainter.width / 2, textPainter.height / 2),
      );
      return;
    }
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
