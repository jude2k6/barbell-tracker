import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../workout/load_velocity.dart';
import '../format.dart';

/// Weight (x) against set velocity (y), one dot per set, joined in weight
/// order. An optional comparison session is drawn as a second series.
/// Tapping near a current-session dot selects that set. Port of Stance's
/// `WeightVelocityChart`: raw points only, no fitted line.
class LoadVelocityChart extends StatelessWidget {
  const LoadVelocityChart({
    super.key,
    required this.data,
    required this.weightLabel,
    this.selectedSetIndex,
    this.onSelect,
    this.height = 220,
  });

  final LoadVelocityData data;

  /// X-axis caption, e.g. "Weight (kg)".
  final String weightLabel;

  /// Set index of the highlighted point.
  final int? selectedSetIndex;
  final ValueChanged<int>? onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final painter = LoadVelocityPainter(
      data: data,
      weightLabel: weightLabel,
      selectedSetIndex: selectedSetIndex,
      color: scheme.primary,
      comparisonColor: scheme.tertiary,
      gridColor: scheme.outlineVariant,
      labelStyle: theme.textTheme.labelSmall!.copyWith(
        color: scheme.onSurfaceVariant,
        fontFeatures: tabularFigures,
      ),
    );
    return Semantics(
      label: 'Weight against velocity, ${data.points.length} sets',
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, box) => GestureDetector(
            onTapUp: onSelect == null
                ? null
                : (d) {
                    final i = painter.nearestSet(d.localPosition, box.biggest);
                    if (i != null) onSelect!(i);
                  },
            child: CustomPaint(
                painter: painter, child: const SizedBox.expand()),
          ),
        ),
      ),
    );
  }
}

class LoadVelocityPainter extends CustomPainter {
  LoadVelocityPainter({
    required this.data,
    required this.weightLabel,
    required this.selectedSetIndex,
    required this.color,
    required this.comparisonColor,
    required this.gridColor,
    required this.labelStyle,
  });

  final LoadVelocityData data;
  final String weightLabel;
  final int? selectedSetIndex;
  final Color color, comparisonColor, gridColor;
  final TextStyle labelStyle;

  // Stance's plot insets.
  static const _left = 48.0, _right = 16.0, _top = 16.0, _bottom = 36.0;

  /// Stance's tap radius (Manhattan distance, px).
  static const _tapRadius = 60.0;

  Rect _plot(Size size) =>
      Rect.fromLTRB(_left, _top, size.width - _right, size.height - _bottom);

  Offset _at(Rect plot, double weight, double velocity) {
    final b = data.bounds;
    final wSpan = math.max(b.maxWeight - b.minWeight, 0.001);
    final vSpan = math.max(b.maxVelocity - b.minVelocity, 0.001);
    return Offset(
      plot.left + (weight - b.minWeight) / wSpan * plot.width,
      plot.bottom - (velocity - b.minVelocity) / vSpan * plot.height,
    );
  }

  /// Set index of the current-session point nearest [pos], if close enough.
  int? nearestSet(Offset pos, Size size) {
    final plot = _plot(size);
    int? best;
    var bestDist = double.infinity;
    for (final p in data.points) {
      final o = _at(plot, p.weight, p.velocity);
      final d = (pos.dx - o.dx).abs() + (pos.dy - o.dy).abs();
      if (d < bestDist) {
        bestDist = d;
        best = p.setIndex;
      }
    }
    return bestDist < _tapRadius ? best : null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final plot = _plot(size);
    final b = data.bounds;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (final v in niceTicks(b.minVelocity, b.maxVelocity, 5)) {
      final y = _at(plot, b.minWeight, v).dy;
      if (y < plot.top - 0.5 || y > plot.bottom + 0.5) continue;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _text(canvas, v.toStringAsFixed(1), Offset(plot.left - 6, y),
          align: _Align.rightMiddle);
    }
    for (final w in niceTicks(b.minWeight, b.maxWeight, 5)) {
      final x = _at(plot, w, b.minVelocity).dx;
      if (x < plot.left - 0.5 || x > plot.right + 0.5) continue;
      _dashed(canvas, Offset(x, plot.top), Offset(x, plot.bottom), grid,
          dash: 6, gap: 10);
      _text(canvas, fmtNumber(w.roundToDouble()), Offset(x, plot.bottom + 4),
          align: _Align.topCenter);
    }
    _text(canvas, 'm/s', const Offset(0, 0));
    _text(canvas, weightLabel, Offset(plot.center.dx, size.height),
        align: _Align.bottomCenter);

    _series(canvas, plot, data.comparisonPoints, comparisonColor, null);
    _series(canvas, plot, data.points, color, selectedSetIndex);

    LoadVelocityPoint? sel;
    for (final p in data.points) {
      if (p.setIndex == selectedSetIndex) sel = p;
    }
    if (sel != null) {
      final o = _at(plot, sel.weight, sel.velocity);
      final cross = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = 2;
      _dashed(canvas, Offset(o.dx, plot.top), Offset(o.dx, plot.bottom), cross,
          dash: 8, gap: 6);
      _dashed(canvas, Offset(plot.left, o.dy), Offset(plot.right, o.dy), cross,
          dash: 8, gap: 6);
      canvas.drawCircle(o, 12, Paint()..color = color.withValues(alpha: 0.35));
      canvas.drawCircle(o, 6, Paint()..color = Colors.white);
      canvas.drawCircle(o, 4.5, Paint()..color = color);
      final style = labelStyle.copyWith(color: color, fontSize: 12);
      _text(canvas, sel.velocity.toStringAsFixed(2),
          Offset(plot.right, o.dy - 2),
          align: _Align.bottomRight, style: style);
      _text(canvas, fmtNumber(sel.weight), Offset(o.dx, plot.top - 2),
          align: _Align.bottomCenter, style: style);
    }
  }

  void _series(Canvas canvas, Rect plot, List<LoadVelocityPoint> pts,
      Color c, int? skip) {
    if (pts.length >= 2) {
      final sorted = [...pts]..sort((a, b) => a.weight.compareTo(b.weight));
      final path = Path();
      for (final (i, p) in sorted.indexed) {
        final o = _at(plot, p.weight, p.velocity);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
    }
    for (final p in pts) {
      if (p.setIndex == skip) continue;
      final o = _at(plot, p.weight, p.velocity);
      canvas.drawCircle(o, 10, Paint()..color = c.withValues(alpha: 0.35));
      canvas.drawCircle(o, 4.5, Paint()..color = c);
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint,
      {required double dash, required double gap}) {
    final len = (b - a).distance;
    if (len == 0) return;
    final dir = (b - a) / len;
    for (var t = 0.0; t < len; t += dash + gap) {
      canvas.drawLine(a + dir * t, a + dir * math.min(t + dash, len), paint);
    }
  }

  void _text(Canvas canvas, String s, Offset at,
      {_Align align = _Align.topLeft, TextStyle? style}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style ?? labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final shift = switch (align) {
      _Align.topLeft => Offset.zero,
      _Align.topCenter => Offset(tp.width / 2, 0),
      _Align.bottomCenter => Offset(tp.width / 2, tp.height),
      _Align.bottomRight => Offset(tp.width, tp.height),
      _Align.rightMiddle => Offset(tp.width, tp.height / 2),
    };
    tp.paint(canvas, at - shift);
  }

  @override
  bool shouldRepaint(LoadVelocityPainter old) =>
      old.data != data ||
      old.selectedSetIndex != selectedSetIndex ||
      old.color != color ||
      old.gridColor != gridColor ||
      old.weightLabel != weightLabel;
}

enum _Align { topLeft, topCenter, bottomCenter, bottomRight, rightMiddle }
