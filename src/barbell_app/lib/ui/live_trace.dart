import 'package:flutter/material.dart';

import '../workout/sensor_controller.dart';
import 'stance_theme.dart';
import 'trace_painter.dart';

/// Live vertical-acceleration trace from the shared sensor, on a Stance
/// card panel (white 4 %, 16 dp corners). Repaints per frame as samples
/// arrive, without rebuilding the surrounding widgets.
class LiveTrace extends StatelessWidget {
  const LiveTrace({
    super.key,
    required this.sensor,
    this.height = 160,
    this.color,
  });

  final SensorController sensor;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: StanceColors.cardFill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: TracePainter(
            values: sensor.traceSnapshot,
            repaint: sensor.traceTick,
            range: 2,
            color: color ?? StanceColors.primaryLight,
            gridColor: const Color(0x1AFFFFFF),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
