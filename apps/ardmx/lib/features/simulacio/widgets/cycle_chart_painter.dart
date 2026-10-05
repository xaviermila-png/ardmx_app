import 'package:flutter/material.dart';

/// One channel's precomputed curve for the whole cycle, ready to draw —
/// [points] are normalized (dx: 0-1 across the full cycle duration, dy:
/// 0-1 for a 0-255 channel value, 0=value 0). Computed once per page/data
/// change in [SimulacioScreen], not per paint call — see that screen's
/// `_buildCurves()`.
class ChannelCurve {
  const ChannelCurve({
    required this.number,
    required this.color,
    required this.points,
    required this.visible,
  });

  /// DMX channel number, matched against [EventMarker.canal].
  final int number;
  final Color color;
  final List<Offset> points;
  final bool visible;
}

/// One programmed event's (V77, ARDMX EVO only) marker on the chart —
/// [position] and [endPosition] are normalized (0-1) the same way as
/// [ChannelCurve.points]' dx, from the event's "moment" to moment+durada over
/// the cycle's total duration. [label] is `"E<n+1>"` (the event's 1-based
/// slot number, not its wire index) — see `SimulacioScreen._loadEvents()`.
/// [canal]/[valor] draw a level pulse on that channel's curve; [pista] is the
/// sound track to show next to the label. Each is null when not set.
class EventMarker {
  const EventMarker({
    required this.position,
    required this.endPosition,
    required this.label,
    this.canal,
    this.valor,
    this.pista,
  });

  final double position;
  final double endPosition;
  final String label;
  final int? canal;
  final int? valor;
  final int? pista;
}

/// Draws the DMX cycle chart: up to 12 channel curves over a timeline whose
/// segments are width-proportional to their real duration, alternating
/// scene (flat background)/transition (slightly shaded background)
/// segments, a phase-boundary time scale, vertical markers for any
/// programmed events, and — while the device is playing — a live position
/// marker.
class CycleChartPainter extends CustomPainter {
  const CycleChartPainter({
    required this.curves,
    required this.periodBoundaries,
    required this.boundaryLabels,
    required this.livePosition,
    required this.onSurfaceColor,
    required this.gridColor,
    this.eventMarkers = const [],
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

  /// Programmed events (EVO only) — empty for the ARDMX One v2 (which has
  /// no V77) or while a device with events genuinely has none configured.
  final List<EventMarker> eventMarkers;

  static const _eventMarkerColor = Colors.amber;
  static const _soundIcon = Icons.volume_up;

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

    double xOf(double normalized) =>
        plotRect.left + normalized * plotRect.width;
    double yOf(double value0to1) =>
        plotRect.bottom - value0to1 * plotRect.height;

    _paintPhaseBackgrounds(canvas, plotRect, xOf);
    _paintYAxis(canvas, plotRect, yOf);
    _paintPhaseBoundaries(canvas, plotRect, xOf);
    _paintCurves(canvas, plotRect, xOf, yOf);
    _paintEventPulses(canvas, plotRect, xOf, yOf);
    _paintEventMarkers(canvas, plotRect, xOf);
    if (livePosition != null) {
      _paintLivePosition(canvas, plotRect, xOf(livePosition!));
    }
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
      canvas.drawLine(
        Offset(plotRect.left, y),
        Offset(plotRect.right, y),
        linePaint,
      );
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
      canvas.drawLine(
        Offset(x, plotRect.top),
        Offset(x, plotRect.bottom),
        linePaint,
      );
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
      final gaps = [
        for (final m in eventMarkers)
          if (m.canal == curve.number && m.valor != null)
            (m.position, m.endPosition),
      ];
      final runs = gaps.isEmpty
          ? [curve.points]
          : _visibleRuns(curve.points, gaps);
      final paint = Paint()
        ..color = curve.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (final run in runs) {
        final path = Path();
        var first = true;
        for (final p in run) {
          final mapped = Offset(xOf(p.dx), yOf(p.dy));
          if (first) {
            path.moveTo(mapped.dx, mapped.dy);
            first = false;
          } else {
            path.lineTo(mapped.dx, mapped.dy);
          }
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  /// Splits [points] into the pieces that stay outside every (start, end)
  /// gap — a gap is where an event's pulse replaces the channel's own level,
  /// so the curve must not be drawn there.
  static List<List<Offset>> _visibleRuns(
    List<Offset> points,
    List<(double, double)> gaps,
  ) {
    final xs = <double>{
      for (final p in points) p.dx,
      for (final g in gaps) ...[g.$1, g.$2],
    }.toList()..sort();
    final runs = <List<Offset>>[];
    List<Offset>? current;
    for (var i = 0; i < xs.length - 1; i++) {
      final a = xs[i];
      final b = xs[i + 1];
      final mid = (a + b) / 2;
      if (gaps.any((g) => mid > g.$1 && mid < g.$2)) {
        current = null;
        continue;
      }
      if (current == null) {
        current = [Offset(a, _levelAt(points, a))];
        runs.add(current);
      }
      current.add(Offset(b, _levelAt(points, b)));
    }
    return runs;
  }

  /// While an event runs, its channel is forced to [EventMarker.valor]: draw
  /// that as a pulse on the channel's own curve — rise from the curve's level
  /// at the start, hold at valor, drop back at the end.
  void _paintEventPulses(
    Canvas canvas,
    Rect plotRect,
    double Function(double) xOf,
    double Function(double) yOf,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    for (final marker in eventMarkers) {
      final canal = marker.canal;
      final valor = marker.valor;
      if (canal == null || valor == null) continue;
      final curve = _visibleCurveFor(canal);
      if (curve == null) continue;
      final x0 = xOf(marker.position);
      final x1 = xOf(marker.endPosition);
      final path = Path()
        ..moveTo(x0, yOf(_levelAt(curve.points, marker.position)))
        ..lineTo(x0, yOf(valor / 255))
        ..lineTo(x1, yOf(valor / 255))
        ..lineTo(x1, yOf(_levelAt(curve.points, marker.endPosition)));
      canvas.drawPath(path, paint..color = curve.color);
    }
  }

  ChannelCurve? _visibleCurveFor(int number) {
    for (final curve in curves) {
      if (curve.number == number && curve.visible && curve.points.isNotEmpty) {
        return curve;
      }
    }
    return null;
  }

  /// Curve level (0-1) at normalized x [dx], linearly interpolated between
  /// the sampled points.
  static double _levelAt(List<Offset> points, double dx) {
    if (dx <= points.first.dx) return points.first.dy;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      if (dx <= b.dx) {
        final span = b.dx - a.dx;
        if (span <= 0) return b.dy;
        return a.dy + (b.dy - a.dy) * (dx - a.dx) / span;
      }
    }
    return points.last.dy;
  }

  /// Full-height vertical line per event, in a color distinct from both the
  /// phase-boundary grid (gridColor) and the dashed live marker
  /// (onSurfaceColor), plus a small filled `"E<n>"` tag pinned to the top
  /// of the line — same x-mapping ([xOf]) as everything else on this chart, so
  /// a marker always lines up with the exact channel-curve sample at that
  /// moment regardless of the (non-uniform) scene/transition segment
  /// widths.
  void _paintEventMarkers(
    Canvas canvas,
    Rect plotRect,
    double Function(double) xOf,
  ) {
    if (eventMarkers.isEmpty) return;
    final linePaint = Paint()
      ..color = onSurfaceColor
      ..strokeWidth = 1.5;

    // Groups markers that land on the same pixel column (e.g. two events at
    // the same "moment") — confirmed on real hardware: drawing them at the
    // exact same x meant each tag fully covered the previous one, so only
    // the last event ever showed a label. Stack the tags vertically instead
    // (E1's tag, then E2's just below it, ...); the line itself only needs
    // drawing once per column since they're all identical there.
    final groups = <int, List<EventMarker>>{};
    for (final marker in eventMarkers) {
      final x = xOf(marker.position.clamp(0.0, 1.0)).round();
      groups.putIfAbsent(x, () => []).add(marker);
    }

    for (final group in groups.entries) {
      final x = group.key.toDouble();
      _drawDashedLine(
        canvas,
        Offset(x, plotRect.top),
        Offset(x, plotRect.bottom),
        linePaint,
      );

      var tagTop = plotRect.top;
      for (final marker in group.value) {
        final pista = marker.pista;
        final tp = TextPainter(
          text: TextSpan(
            style: const TextStyle(
              color: Colors.black,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
            children: [
              TextSpan(text: marker.label),
              if (pista != null) ...[
                TextSpan(
                  text: ' ${String.fromCharCode(_soundIcon.codePoint)}',
                  style: TextStyle(
                    fontFamily: _soundIcon.fontFamily,
                    fontSize: 10,
                  ),
                ),
                TextSpan(text: '$pista'),
              ],
            ],
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final tagLeft = (x - tp.width / 2 - 2).clamp(
          plotRect.left,
          plotRect.right - tp.width - 4,
        );
        final tagRect = Rect.fromLTWH(
          tagLeft,
          tagTop,
          tp.width + 4,
          tp.height + 2,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(tagRect, const Radius.circular(3)),
          Paint()..color = _eventMarkerColor,
        );
        tp.paint(canvas, Offset(tagLeft + 2, tagTop + 1));
        tagTop += tp.height + 3;
      }
    }
  }

  void _paintLivePosition(Canvas canvas, Rect plotRect, double x) {
    final paint = Paint()
      ..color = onSurfaceColor
      ..strokeWidth = 2;
    _drawDashedLine(
      canvas,
      Offset(x, plotRect.top),
      Offset(x, plotRect.bottom),
      paint,
    );
    canvas.drawCircle(
      Offset(x, plotRect.top),
      4,
      Paint()..color = onSurfaceColor,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashLength = 5.0;
    const gapLength = 4.0;
    final total = (b - a).distance;
    final direction = (b - a) / total;
    var covered = 0.0;
    while (covered < total) {
      final segmentEnd = (covered + dashLength).clamp(0.0, total);
      canvas.drawLine(
        a + direction * covered,
        a + direction * segmentEnd,
        paint,
      );
      covered += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant CycleChartPainter oldDelegate) {
    return oldDelegate.curves != curves ||
        oldDelegate.periodBoundaries != periodBoundaries ||
        oldDelegate.livePosition != livePosition ||
        oldDelegate.eventMarkers != eventMarkers;
  }
}
