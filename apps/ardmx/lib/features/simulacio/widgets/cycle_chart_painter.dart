import 'package:flutter/material.dart';

/// One channel's precomputed curve for the whole cycle, ready to draw —
/// [points] are normalized (dx: 0-1 across the full cycle duration, dy:
/// 0-1 for a 0-255 channel value, 0=value 0). Computed once per page/data
/// change in [SimulacioScreen], not per paint call — see that screen's
/// `_buildCurves()`.
class ChannelCurve {
  const ChannelCurve({
    required this.color,
    required this.points,
    required this.visible,
  });

  final Color color;
  final List<Offset> points;
  final bool visible;
}

/// Draws the DMX cycle chart: up to 12 channel curves over a timeline whose
/// segments are width-proportional to their real duration, alternating
/// scene (flat background)/transition (slightly shaded background)
/// segments, a phase-boundary time scale, and — while the device is
/// playing — a live position marker.
class CycleChartPainter extends CustomPainter {
  const CycleChartPainter({
    required this.curves,
    required this.periodBoundaries,
    required this.boundaryLabels,
    required this.livePosition,
    required this.onSurfaceColor,
    required this.gridColor,
  });

  /// Normalized (0-1) x position of each phase boundary, including 0 and 1
  /// — length is periodCount+1. `periodBoundaries[i]` to
  /// `periodBoundaries[i+1]` is period `i` (even=scene, odd=transition).
  final List<double> periodBoundaries;

  /// One label per boundary (accumulated seconds, e.g. "0s", "5s"...) —
  /// same length as [periodBoundaries].
  final List<String> boundaryLabels;

  final List<ChannelCurve> curves;

  /// Normalized (0-1) position of the live playback marker, or `null` when
  /// the device isn't currently playing (no marker drawn).
  final double? livePosition;

  final Color onSurfaceColor;
  final Color gridColor;

  static const _leftMargin = 32.0;
  static const _bottomMargin = 16.0;
  static const _topMargin = 6.0;
  static const _rightMargin = 6.0;
  static const _yMarks = [0, 64, 128, 192, 255];

  @override
  void paint(Canvas canvas, Size size) {
    final plotRect = Rect.fromLTWH(
      _leftMargin,
      _topMargin,
      size.width - _leftMargin - _rightMargin,
      size.height - _topMargin - _bottomMargin,
    );
    if (plotRect.width <= 0 || plotRect.height <= 0) return;

    double xOf(double normalized) => plotRect.left + normalized * plotRect.width;
    double yOf(double value0to1) =>
        plotRect.bottom - value0to1 * plotRect.height;

    _paintPhaseBackgrounds(canvas, plotRect, xOf);
    _paintYAxis(canvas, plotRect, yOf);
    _paintPhaseBoundaries(canvas, plotRect, xOf);
    _paintCurves(canvas, plotRect, xOf, yOf);
    if (livePosition != null) _paintLivePosition(canvas, plotRect, xOf(livePosition!));
  }

  void _paintPhaseBackgrounds(
    Canvas canvas,
    Rect plotRect,
    double Function(double) xOf,
  ) {
    final transitionPaint = Paint()..color = gridColor.withValues(alpha: 0.08);
    for (var i = 0; i < periodBoundaries.length - 1; i++) {
      if (i.isEven) continue; // only shade transitions, scenes stay plain
      final left = xOf(periodBoundaries[i]);
      final right = xOf(periodBoundaries[i + 1]);
      canvas.drawRect(
        Rect.fromLTRB(left, plotRect.top, right, plotRect.bottom),
        transitionPaint,
      );
    }
  }

  void _paintYAxis(Canvas canvas, Rect plotRect, double Function(double) yOf) {
    final linePaint = Paint()
      ..color = gridColor.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    for (final mark in _yMarks) {
      final y = yOf(mark / 255);
      canvas.drawLine(Offset(plotRect.left, y), Offset(plotRect.right, y), linePaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '$mark',
          style: TextStyle(color: onSurfaceColor, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }
  }

  void _paintPhaseBoundaries(
    Canvas canvas,
    Rect plotRect,
    double Function(double) xOf,
  ) {
    final linePaint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 0; i < periodBoundaries.length; i++) {
      final x = xOf(periodBoundaries[i]);
      canvas.drawLine(Offset(x, plotRect.top), Offset(x, plotRect.bottom), linePaint);
      final tp = TextPainter(
        text: TextSpan(
          text: boundaryLabels[i],
          style: TextStyle(color: onSurfaceColor, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Clamp so the first/last label don't spill past the plot area.
      final left = (x - tp.width / 2).clamp(0.0, plotRect.right - tp.width);
      tp.paint(canvas, Offset(left, plotRect.bottom + 2));
    }
  }

  void _paintCurves(
    Canvas canvas,
    Rect plotRect,
    double Function(double) xOf,
    double Function(double) yOf,
  ) {
    for (final curve in curves) {
      if (!curve.visible || curve.points.isEmpty) continue;
      final path = Path();
      var first = true;
      for (final p in curve.points) {
        final mapped = Offset(xOf(p.dx), yOf(p.dy));
        if (first) {
          path.moveTo(mapped.dx, mapped.dy);
          first = false;
        } else {
          path.lineTo(mapped.dx, mapped.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = curve.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _paintLivePosition(Canvas canvas, Rect plotRect, double x) {
    final paint = Paint()
      ..color = onSurfaceColor
      ..strokeWidth = 2;
    _drawDashedLine(canvas, Offset(x, plotRect.top), Offset(x, plotRect.bottom), paint);
    canvas.drawCircle(Offset(x, plotRect.top), 4, Paint()..color = onSurfaceColor);
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashLength = 5.0;
    const gapLength = 4.0;
    final total = (b - a).distance;
    final direction = (b - a) / total;
    var covered = 0.0;
    while (covered < total) {
      final segmentEnd = (covered + dashLength).clamp(0.0, total);
      canvas.drawLine(a + direction * covered, a + direction * segmentEnd, paint);
      covered += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant CycleChartPainter oldDelegate) {
    return oldDelegate.curves != curves ||
        oldDelegate.periodBoundaries != periodBoundaries ||
        oldDelegate.livePosition != livePosition;
  }
}
