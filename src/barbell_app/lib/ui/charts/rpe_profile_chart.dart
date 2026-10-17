import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../workout/load_velocity.dart' show niceTicks;
import '../../workout/rpe_profile.dart';
import '../app_theme.dart';
import '../format.dart';
import 'rep_velocity_chart.dart' show chartAxisLabel;

/// Stance's RPE colour scale, 5 (grey-blue) to 10 (red) in 0.5 steps.
const _rpeColors = [
  Color(0xff736984), Color(0xff5e7ab9), Color(0xff498aee), Color(0xff54a2a5),
  Color(0xff5eba5c), Color(0xffa7cb41), Color(0xfff0dc25), Color(0xffeea825),
  Color(0xffeb7325), Color(0xffea633c), Color(0xffe85252),
];

/// Stance's colour for [rpe], or null off the 5–10 half-step scale.
Color? rpeColor(double rpe) {
  final i = rpe * 2 - 10;
  if (i != i.roundToDouble() || i < 0 || i >= _rpeColors.length) return null;
  return _rpeColors[i.toInt()];
}

/// RPE (x) against last-rep speed (y): every tagged set as a tick, the
/// interquartile range as a bar, and the rated set's speed as a line.
/// Zoomed in, the axes show only the suggested RPE range and the ±20 %
/// speed window; zoomed out, RPE 5–10 and all speeds. Port of Stance's
/// `RpeIntensityProfileChart`.
class RpeProfileChart extends StatefulWidget {
  const RpeProfileChart({super.key, required this.profile, this.height = 220});

  final RpeIntensityProfile profile;
  final double height;

  @override
  State<RpeProfileChart> createState() => _RpeProfileChartState();
}

class _RpeProfileChartState extends State<RpeProfileChart> {
  bool _zoomedOut = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.profile;
    if (p.isEmpty) {
      return SizedBox(
        height: 60,
        child: Center(
          child: Text('No data to display',
              style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.subtitleGray, fontWeight: FontWeight.w700)),
        ),
      );
    }
    return Stack(children: [
      Semantics(
        label: 'Speed-intensity profile, ${p.points.length} RPE values',
        child: SizedBox(
          height: widget.height,
          child: CustomPaint(
            painter: RpeProfilePainter(
              profile: p,
              zoomedOut: _zoomedOut,
              lineColor: AppColors.primary,
              gridColor: const Color(0x26FFFFFF),
              labelStyle: chartAxisLabel,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
      Positioned(
        top: 0,
        right: 0,
        child: IconButton(
          key: const Key('rpeChartZoom'),
          tooltip: _zoomedOut ? 'Zoom in' : 'Zoom out',
          visualDensity: VisualDensity.compact,
          icon: Icon(_zoomedOut ? Icons.zoom_in : Icons.zoom_out),
          onPressed: () => setState(() => _zoomedOut = !_zoomedOut),
        ),
      ),
    ]);
  }
}

class RpeProfilePainter extends CustomPainter {
  RpeProfilePainter({
    required this.profile,
    required this.zoomedOut,
    required this.lineColor,
    required this.gridColor,
    required this.labelStyle,
  });

  final RpeIntensityProfile profile;
  final bool zoomedOut;
  final Color lineColor, gridColor;
  final TextStyle labelStyle;

  // Stance's plot insets.
  static const _left = 48.0, _right = 8.0, _top = 8.0, _bottom = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final p = profile;
    final plot =
        Rect.fromLTRB(_left, _top, size.width - _right, size.height - _bottom);

    final double x0, x1, y0, y1;
    if (zoomedOut) {
      final absMax = p.points.map((e) => e.absoluteMax).fold(0.0, math.max);
      x0 = 4.8;
      x1 = 10.2;
      y0 = 0;
      y1 = (absMax > 0 ? absMax : 1.0) * 1.2;
    } else {
      final hasWindow = p.maxSpeed > p.minSpeed;
      x0 = p.minRpe - 0.2;
      x1 = p.maxRpe + 0.2;
      y0 = hasWindow ? p.minSpeed : 0;
      y1 = hasWindow ? p.maxSpeed : 1;
    }
    final xSpan = math.max(x1 - x0, 1e-6), ySpan = math.max(y1 - y0, 1e-6);
    double x(double rpe) => plot.left + (rpe - x0) / xSpan * plot.width;
    double y(double v) => plot.bottom - (v - y0) / ySpan * plot.height;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (final v in niceTicks(y0, y1, 5)) {
      if (v < y0 - 1e-9 || v > y1 + 1e-9) continue;
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), grid);
      _text(canvas, v.toStringAsFixed(2), Offset(plot.left - 6, y(v)),
          rightMiddle: true);
    }
    for (var r = (x0 * 2).ceil() / 2; r <= x1; r += 0.5) {
      if (r < 5 || r > 10) continue;
      _text(canvas, fmtRpe(r), Offset(x(r), plot.bottom + 6));
    }
    _text(canvas, 'm/s', const Offset(0, 0), topLeft: true);
    _text(canvas, 'RPE', Offset(plot.center.dx, size.height - 12));

    canvas.save();
    canvas.clipRect(plot);
    // Stance draws each logged speed as a bar ±0.6 % of the axis tall.
    final tick = ySpan * 0.006;
    for (final pt in p.points) {
      final c = rpeColor(pt.rpe) ?? lineColor;
      final cx = x(pt.rpe);
      final tickPaint = Paint()..color = c.withValues(alpha: 0.7);
      for (final v in pt.velocities) {
        final top = y(v + tick), bottom = y(v - tick);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(cx - 11, top, cx + 11, math.max(bottom, top + 1.5)),
            const Radius.circular(1),
          ),
          tickPaint,
        );
      }
      final lo = math.max(pt.minVelocity, y0), hi = math.min(pt.maxVelocity, y1);
      if (hi > lo) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(cx - 4, y(hi), cx + 4, y(lo)),
            const Radius.circular(4),
          ),
          Paint()..color = c,
        );
      }
    }
    canvas.restore();

    final speed = p.lastRepSpeed;
    if (speed != null && speed >= y0 && speed <= y1) {
      canvas.drawLine(
        Offset(plot.left, y(speed)),
        Offset(plot.right, y(speed)),
        Paint()
          ..color = lineColor
          ..strokeWidth = 2,
      );
      _text(canvas, speed.toStringAsFixed(2), Offset(plot.left + 4, y(speed) - 2),
          topLeft: true,
          above: true,
          style: labelStyle.copyWith(color: lineColor));
    }
  }

  void _text(Canvas canvas, String s, Offset at,
      {bool rightMiddle = false,
      bool topLeft = false,
      bool above = false,
      TextStyle? style}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style ?? labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final shift = rightMiddle
        ? Offset(tp.width, tp.height / 2)
        : topLeft
            ? Offset(0, above ? tp.height : 0)
            : Offset(tp.width / 2, 0);
    tp.paint(canvas, at - shift);
  }

  @override
  bool shouldRepaint(RpeProfilePainter old) =>
      old.profile != profile ||
      old.zoomedOut != zoomedOut ||
      old.lineColor != lineColor ||
      old.gridColor != gridColor;
}
