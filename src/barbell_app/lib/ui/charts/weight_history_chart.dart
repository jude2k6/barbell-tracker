import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../workout/load_velocity.dart';
import '../format.dart';
import '../stance_theme.dart';
import 'rep_velocity_chart.dart' show stanceAxisLabel;

/// Earlier sets at one weight: a bar from the slowest to the fastest rep
/// mean velocity, newest on the right and highlighted. Always
/// [weightHistoryMaxPoints] slots wide, padded on the left. Port of
/// Stance's `WeightMinMaxBarChart`.
class WeightHistoryChart extends StatelessWidget {
  const WeightHistoryChart({super.key, required this.points, this.height = 160});

  final List<WeightHistoryPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Velocity range of the last ${points.length} sets at this weight',
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: WeightHistoryPainter(
            points: points,
            // Stance: newest Primary, earlier SecondaryPrime, white 15 %
            // grid, 11 sp white labels.
            latestColor: StanceColors.primary,
            color: StanceColors.secondaryPrime,
            gridColor: const Color(0x26FFFFFF),
            labelStyle: stanceAxisLabel.copyWith(color: Colors.white),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class WeightHistoryPainter extends CustomPainter {
  WeightHistoryPainter({
    required this.points,
    required this.latestColor,
    required this.color,
    required this.gridColor,
    required this.labelStyle,
  });

  final List<WeightHistoryPoint> points;
  final Color latestColor, color, gridColor;
  final TextStyle labelStyle;

  static const _left = 36.0, _right = 10.0, _top = 8.0, _bottom = 30.0;
  static const _barWidth = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final plot = Rect.fromLTRB(
        _left, _top, size.width - _right, size.height - _bottom);
    // Stance: y from 0 to the highest max, at least 1 m/s.
    final yMax = math.max(points.map((p) => p.maxVelocity).reduce(math.max), 1.0);
    double y(double v) => plot.bottom - v / yMax * plot.height;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (final v in niceTicks(0, yMax, 5)) {
      if (v > yMax + 1e-9) continue;
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), grid);
      _text(canvas, v.toStringAsFixed(1), Offset(plot.left - 6, y(v)),
          rightMiddle: true);
    }

    const slots = weightHistoryMaxPoints;
    final pitch = (plot.width - 2 * 10) / (slots - 1);
    final pad = slots - points.length;
    for (final (i, p) in points.indexed) {
      final slot = pad + i;
      final x = plot.left + 10 + slot * pitch;
      final top = y(p.maxVelocity);
      final h = math.max(y(p.minVelocity) - top, 2.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - _barWidth / 2, top, _barWidth, h),
          const Radius.circular(_barWidth / 2),
        ),
        Paint()..color = slot == slots - 1 ? latestColor : color,
      );
      _text(canvas, '${p.date.day}', Offset(x, plot.bottom + 4));
      _text(canvas, fmtMonth(p.date), Offset(x, plot.bottom + 16));
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
  bool shouldRepaint(WeightHistoryPainter old) =>
      old.points != points ||
      old.color != color ||
      old.latestColor != latestColor;
}
