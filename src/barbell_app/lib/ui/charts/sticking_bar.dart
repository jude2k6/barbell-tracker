import 'package:flutter/material.dart';

import '../../workout/session.dart';

/// Colours for the sticking-region bands, matching the reference app.
const stickingOrange = Color(0xFFF59E0B);
const stickingRed = Color(0xFFDC2626);

/// Horizontal 0–100 % range-of-motion bar: orange band where velocity fell
/// below 75 % of its early peak, red band below 32.5 %, and a tick at the
/// sticking point.
class StickingBar extends StatelessWidget {
  const StickingBar({super.key, required this.sticking, this.height = 14});

  final StickingRecord sticking;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = sticking;
    final label = StringBuffer(
        'Sticking region ${s.startPct.round()} to ${s.endPct.round()} percent');
    if (s.minVelocityPct != null) {
      label.write(', sticking point ${s.minVelocityPct!.round()} percent');
    }
    return Semantics(
      label: label.toString(),
      child: SizedBox(
        height: height + 6,
        child: CustomPaint(
          painter: _StickingBarPainter(
            sticking: s,
            track: scheme.surfaceContainerHighest,
            tick: scheme.onSurface,
            barHeight: height,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _StickingBarPainter extends CustomPainter {
  _StickingBarPainter({
    required this.sticking,
    required this.track,
    required this.tick,
    required this.barHeight,
  });

  final StickingRecord sticking;
  final Color track, tick;
  final double barHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final top = (size.height - barHeight) / 2;
    final bar = Rect.fromLTWH(0, top, size.width, barHeight);
    final radius = Radius.circular(barHeight / 2);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(bar, radius));
    canvas.drawRect(bar, Paint()..color = track);

    double x(double pct) => (pct.clamp(0, 100) / 100) * size.width;
    void band(double from, double to, Color c) => canvas.drawRect(
        Rect.fromLTRB(x(from), top, x(to), top + barHeight), Paint()..color = c);

    band(sticking.startPct, sticking.endPct, stickingOrange);
    if (sticking.hasSevere) {
      band(sticking.severeStartPct!, sticking.severeEndPct!, stickingRed);
    }
    canvas.restore();

    final min = sticking.minVelocityPct;
    if (min != null) {
      final xx = x(min);
      canvas.drawLine(
        Offset(xx, 0),
        Offset(xx, size.height),
        Paint()
          ..color = tick
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_StickingBarPainter old) =>
      old.sticking != sticking || old.track != track || old.tick != tick;
}
