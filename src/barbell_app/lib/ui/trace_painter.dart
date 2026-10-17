import 'package:flutter/material.dart';

/// Scrolling line plot of recent values with a fixed symmetric range.
///
/// [values] is read at paint time, so pass a [repaint] listenable that
/// fires when new values arrive to redraw without rebuilding widgets.
class TracePainter extends CustomPainter {
  TracePainter({
    required this.values,
    required this.range,
    required this.color,
    required this.gridColor,
    super.repaint,
  });

  final List<double> Function() values;
  final double range;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), grid);
    final values = this.values();
    if (values.length < 2) return;

    final path = Path();
    final dx = size.width / (values.length - 1);
    for (var i = 0; i < values.length; i++) {
      final v = values[i].clamp(-range, range);
      final y = mid - v / range * mid;
      i == 0 ? path.moveTo(0, y) : path.lineTo(i * dx, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(TracePainter old) =>
      old.range != range || old.color != color || old.gridColor != gridColor;
}
