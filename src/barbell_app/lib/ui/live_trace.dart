import 'package:flutter/material.dart';

import '../workout/sensor_controller.dart';
import 'trace_painter.dart';

/// Live vertical-acceleration trace from the shared sensor. Repaints per
/// frame as samples arrive, without rebuilding the surrounding widgets.
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
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: TracePainter(
            values: sensor.traceSnapshot,
            repaint: sensor.traceTick,
            range: 2,
            color: color ?? scheme.primary,
            gridColor: scheme.outlineVariant,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
