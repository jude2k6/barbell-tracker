import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../workout/load_velocity.dart' show niceTicks;
import '../../workout/session_comparison.dart';
import '../format.dart';

/// Mean velocity per rep as a smoothed line with dots, optionally against
/// a second set's reps. Port of Stance's `RepVelocityChart`.
class RepVelocityChart extends StatelessWidget {
  const RepVelocityChart({
    super.key,
    required this.velocities,
    this.compare = const [],
    this.bounds,
    this.showAxes = true,
    this.height = 160,
  });

  final List<double> velocities;

  /// The comparison set's rep velocities, drawn underneath.
  final List<double> compare;

  /// Fixed y range, e.g. shared across several charts.
  final (double, double)? bounds;
  final bool showAxes;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (velocities.isEmpty && compare.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('No data to display',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      );
    }
    return Semantics(
      label: 'Rep speeds, ${velocities.length} reps',
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: RepVelocityPainter(
            velocities: velocities,
            compare: compare,
            bounds: bounds ?? repChartBounds([...velocities, ...compare]),
            showAxes: showAxes,
            color: scheme.primary,
            compareColor: scheme.tertiary,
            gridColor: scheme.outlineVariant,
            labelStyle: theme.textTheme.labelSmall!.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: tabularFigures,
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class RepVelocityPainter extends CustomPainter {
  RepVelocityPainter({
    required this.velocities,
    required this.compare,
    required this.bounds,
    required this.showAxes,
    required this.color,
    required this.compareColor,
    required this.gridColor,
    required this.labelStyle,
  });

  final List<double> velocities, compare;
  final (double, double) bounds;
  final bool showAxes;
  final Color color, compareColor, gridColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    // Stance's insets: 44 left, 8 top/right, 28 bottom.
    final plot = showAxes
        ? Rect.fromLTRB(44, 8, size.width - 8, size.height - 28)
        : Rect.fromLTRB(6, 6, size.width - 6, size.height - 6);
    final (lo, hi) = bounds;
    final n = math.max(velocities.length, compare.length);
    final xSteps = math.max(n - 1, 1);
    double x(int rep) => plot.left + (rep - 1) / xSteps * plot.width;
    double y(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;

    if (showAxes) {
      final grid = Paint()
        ..color = gridColor
        ..strokeWidth = 0.5;
      for (final v in niceTicks(lo, hi, 4)) {
        if (v < lo - 1e-9 || v > hi + 1e-9) continue;
        canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), grid);
        _text(canvas, v.toStringAsFixed(2), Offset(plot.left - 6, y(v)),
            rightMiddle: true);
      }
      final step = math.max(1, (n / 8).ceil());
      for (var rep = 1; rep <= n; rep += step) {
        _text(canvas, '$rep', Offset(x(rep), plot.bottom + 4));
      }
      _text(canvas, 'Reps', Offset(plot.center.dx, size.height - 12));
    }

    _series(canvas, compare, compareColor, x, y);
    _series(canvas, velocities, color, x, y);
  }

  void _series(Canvas canvas, List<double> v, Color c, double Function(int) x,
      double Function(double) y) {
    if (v.isEmpty) return;
    final pts = [for (final (i, s) in v.indexed) Offset(x(i + 1), y(s))];
    if (pts.length >= 2) {
      canvas.drawPath(
        catmullRomPath(pts),
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    for (final p in pts) {
      canvas.drawCircle(p, 4.5, Paint()..color = c);
    }
  }

  void _text(Canvas canvas, String s, Offset at, {bool rightMiddle = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas,
        at -
            (rightMiddle
                ? Offset(tp.width, tp.height / 2)
                : Offset(tp.width / 2, 0)));
  }

  @override
  bool shouldRepaint(RepVelocityPainter old) =>
      old.velocities != velocities ||
      old.compare != compare ||
      old.bounds != bounds ||
      old.color != color;
}

/// Stance's Catmull-Rom spline through [pts] (endpoints repeated).
Path catmullRomPath(List<Offset> pts) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = i > 0 ? pts[i - 1] : pts[i];
    final p1 = pts[i], p2 = pts[i + 1];
    final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}
