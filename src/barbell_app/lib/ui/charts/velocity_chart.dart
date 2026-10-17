import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../stance_theme.dart';
import 'rep_velocity_chart.dart' show stanceAxisLabel;

/// A rep's concentric window on the velocity chart.
class RepWindow {
  const RepWindow(this.index, this.startSec, this.endSec);
  final int index;
  final double startSec, endSec;
}

/// Bar velocity over the whole set with each rep's concentric phase shaded
/// and numbered.
class VelocityChart extends StatelessWidget {
  const VelocityChart({
    super.key,
    required this.velocity,
    required this.hz,
    required this.reps,
    this.height = 180,
  });

  final List<double> velocity;
  final double hz;
  final List<RepWindow> reps;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Velocity trace with ${reps.length} reps',
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: VelocityChartPainter(
            velocity: velocity,
            hz: hz,
            reps: reps,
            lineColor: StanceColors.primary,
            shadeColor: StanceColors.primary.withValues(alpha: 0.12),
            gridColor: const Color(0x26FFFFFF),
            labelStyle: stanceAxisLabel,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Paints [VelocityChart]. Y axis is m/s with a zero line; X is seconds.
class VelocityChartPainter extends CustomPainter {
  VelocityChartPainter({
    required this.velocity,
    required this.hz,
    required this.reps,
    required this.lineColor,
    required this.shadeColor,
    required this.gridColor,
    required this.labelStyle,
    this.playheadSec,
    this.playheadColor,
  });

  final List<double> velocity;
  final double hz;
  final List<RepWindow> reps;
  final Color lineColor, shadeColor, gridColor;
  final TextStyle labelStyle;

  /// Optional vertical marker, e.g. the current video position.
  final double? playheadSec;
  final Color? playheadColor;

  static const _leftAxis = 32.0;
  static const _bottomAxis = 16.0;
  static const _top = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (velocity.length < 2 || hz <= 0) return;
    final plot = Rect.fromLTRB(
        _leftAxis, _top, size.width, size.height - _bottomAxis);
    final duration = (velocity.length - 1) / hz;

    var vMin = 0.0, vMax = 0.0;
    for (final v in velocity) {
      if (v.isFinite) {
        vMin = math.min(vMin, v);
        vMax = math.max(vMax, v);
      }
    }
    final step = _niceStep((vMax - vMin) / 4);
    vMax = (vMax / step).ceil() * step;
    vMin = (vMin / step).floor() * step;
    if (vMax - vMin < step) vMax = vMin + step;

    double x(double sec) => plot.left + sec / duration * plot.width;
    double y(double v) =>
        plot.bottom - (v - vMin) / (vMax - vMin) * plot.height;

    // Rep windows.
    final shade = Paint()..color = shadeColor;
    for (final r in reps) {
      final rect = Rect.fromLTRB(
        x(r.startSec.clamp(0, duration)),
        plot.top,
        x(r.endSec.clamp(0, duration)),
        plot.bottom,
      );
      canvas.drawRect(rect, shade);
      _text(canvas, '${r.index}', Offset(rect.center.dx, 0), center: true);
    }

    // Grid and Y labels.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var v = vMin; v <= vMax + step / 2; v += step) {
      final yy = y(v);
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy),
          grid..strokeWidth = v.abs() < 1e-9 ? 1.5 : 0.5);
      _text(canvas, v.toStringAsFixed(1), Offset(0, yy - 6));
    }

    // X labels: whole seconds, thinned to fit.
    final secStep = math.max(1, (duration / 6).ceil());
    for (var s = 0; s <= duration; s += secStep) {
      _text(canvas, '${s}s', Offset(x(s.toDouble()), plot.bottom + 2),
          center: true);
    }

    // Trace, decimated to about two points per pixel.
    final stride = math.max(1, velocity.length ~/ (plot.width * 2));
    final path = Path();
    var first = true;
    for (var i = 0; i < velocity.length; i += stride) {
      final v = velocity[i];
      if (!v.isFinite) continue;
      final p = Offset(x(i / hz), y(v));
      first ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      first = false;
    }
    canvas.save();
    canvas.clipRect(plot);
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
    final ph = playheadSec;
    if (ph != null && ph >= 0 && ph <= duration) {
      canvas.drawLine(
        Offset(x(ph), plot.top),
        Offset(x(ph), plot.bottom),
        Paint()
          ..color = playheadColor ?? lineColor
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
  }

  void _text(Canvas canvas, String s, Offset at, {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, 0) : at);
  }

  static double _niceStep(double raw) {
    if (raw <= 0) return 0.5;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final n = raw / mag;
    final nice = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10;
    return nice * mag;
  }

  @override
  bool shouldRepaint(VelocityChartPainter old) =>
      old.velocity != velocity ||
      old.reps != reps ||
      old.hz != hz ||
      old.playheadSec != playheadSec ||
      old.lineColor != lineColor ||
      old.gridColor != gridColor;
}
