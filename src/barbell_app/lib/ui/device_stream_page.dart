import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../workout/device_stream.dart';
import 'app_scope.dart';
import 'sensor_status_chip.dart';
import 'stance_widgets.dart';
import 'workout_flow.dart';

/// Stance's "Test device stream" debug screen: live raw motion data from the
/// sensor as three charts (acceleration, quaternion, global acceleration)
/// with Start / Stop / Clear and the stationary, uncalibrated and
/// streaming-issue badges.
class DeviceStreamPage extends StatefulWidget {
  const DeviceStreamPage({super.key});

  @override
  State<DeviceStreamPage> createState() => _DeviceStreamPageState();
}

class _DeviceStreamPageState extends State<DeviceStreamPage> {
  DeviceStreamController? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= DeviceStreamController(AppScope.of(context).sensor);
  }

  @override
  void dispose() {
    _stream?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final stream = _stream!;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Back button, title and status chip.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  CircleIconButton(
                    icon: Icons.arrow_back,
                    tooltip: 'Go back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        'Test device stream',
                        style: text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  SensorStatusChip(
                    sensor: app.sensor,
                    onPressed: () => openDevice(context),
                  ),
                ],
              ),
            ),
            Expanded(child: _content(context, stream)),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, DeviceStreamController stream) {
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: stream,
      builder: (context, _) {
        final points = stream.points;
        final times = [for (final p in points) p.timeMs];
        // Stance's AccX / AccY / AccZ / Q3 colours.
        const r = Color(0xFF34C759), g = Color(0xFFFF9500);
        const b = Color(0xFF007AFF), o = Color(0xFFFF3B30);
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (!stream.connected)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Text('Device is not connected', style: text.bodySmall),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const Key('streamStart'),
                      onPressed: stream.canStart ? stream.start : null,
                      child: const Text('Start'),
                    ),
                  ),
                  Expanded(
                    child: FilledButton(
                      key: const Key('streamStop'),
                      onPressed: stream.canStop ? stream.stop : null,
                      child: const Text('Stop'),
                    ),
                  ),
                  Expanded(
                    child: FilledButton(
                      key: const Key('streamClear'),
                      onPressed: stream.clear,
                      child: const Text('Clear'),
                    ),
                  ),
                ],
              ),
            ),
            _Badges(stream.heuristics),
            _Legend(const [('Acc X', r), ('Acc Y', g), ('Acc Z', b)]),
            _StreamChart(
              label: 'Acceleration',
              times: times,
              streaming: stream.streaming,
              series: [
                ([for (final p in points) p.ax], r),
                ([for (final p in points) p.ay], g),
                ([for (final p in points) p.az], b),
              ],
            ),
            _Legend(const [('Q0', r), ('Q1', g), ('Q2', b), ('Q3', o)]),
            _StreamChart(
              label: 'Quaternion',
              times: times,
              streaming: stream.streaming,
              series: [
                ([for (final p in points) p.q0], r),
                ([for (final p in points) p.q1], g),
                ([for (final p in points) p.q2], b),
                ([for (final p in points) p.q3], o),
              ],
            ),
            _Legend(const [
              ('Global', Color(0xB3808080)),
              ('Acc X', r),
              ('Acc Y', g),
              ('Acc Z', b),
            ]),
            _StreamChart(
              label: 'Global acceleration',
              times: times,
              streaming: stream.streaming,
              series: [
                ([for (final p in points) p.gx], r),
                ([for (final p in points) p.gy], g),
                ([for (final p in points) p.gz], b),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Badges extends StatelessWidget {
  const _Badges(this.h);

  final StreamHeuristics h;

  @override
  Widget build(BuildContext context) {
    Widget badge(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          badge(
            'Is Stationary',
            h.stationary ? const Color(0xB334C759) : const Color(0xB3808080),
          ),
          if (h.stationary && !h.calibrated)
            badge('Uncalibrated', const Color(0xB3FF0000)),
          if (h.streamingIssue)
            badge('Streaming issue', const Color(0xB3FF0000)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.chips);

  final List<(String, Color)> chips;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 12,
        children: [
          for (final (name, color) in chips)
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Container(width: 10, height: 10, color: color),
                Text(name, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}

/// Stance's `DeviceStreamChart` card (gray 10 %, 10 dp radius, 4 dp shadow):
/// fixed -3..3 range, 200 px high. While streaming it shows
/// the last [liveWindow] points; stopped, the whole run thinned to at most
/// [fullSeriesMaxVertices] points, scrolling sideways when it is long.
class _StreamChart extends StatelessWidget {
  const _StreamChart({
    required this.label,
    required this.times,
    required this.series,
    required this.streaming,
  });

  static const liveWindow = 200;
  static const fullSeriesMaxVertices = 1000;

  final String label;
  final List<int> times;
  final List<(List<double>, Color)> series;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    var t = times;
    var s = series;
    if (streaming) {
      List<T> tail<T>(List<T> l) =>
          l.length > liveWindow ? l.sublist(l.length - liveWindow) : l;
      t = tail(t);
      s = [for (final (v, c) in s) (tail(v), c)];
    } else if (t.length > fullSeriesMaxVertices) {
      final idx = downsampleIndices(t.length, fullSeriesMaxVertices);
      t = [for (final i in idx) t[i]];
      s = [
        for (final (v, c) in s) ([for (final i in idx) v[i]], c),
      ];
    }
    final scrolls = !streaming && t.length > liveWindow;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x1A888888),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              LayoutBuilder(
                builder: (context, box) {
                  final width = scrolls
                      ? math.max(box.maxWidth, t.length * 3.0)
                      : box.maxWidth;
                  final chart = CustomPaint(
                    size: Size(width, 200),
                    painter: _ChartPainter(
                      times: t,
                      series: s,
                      gridColor: Theme.of(context).dividerColor,
                      textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  );
                  return scrolls
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: chart,
                        )
                      : chart;
                },
              ),
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: Text(
                  'Time',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.times,
    required this.series,
    required this.gridColor,
    required this.textColor,
  });

  static const yMin = -3.0, yMax = 3.0;
  static const left = 36.0, right = 12.0, top = 12.0, bottom = 28.0;

  final List<int> times;
  final List<(List<double>, Color)> series;
  final Color gridColor, textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    if (w <= 0 || h <= 0) return;
    double mapY(double v) => top + (1 - (v - yMin) / (yMax - yMin)) * h;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = -3; i <= 3; i++) {
      final y = mapY(i.toDouble());
      canvas.drawLine(Offset(left, y), Offset(left + w, y), grid);
      final tp = TextPainter(
        text: TextSpan(
          text: '$i',
          style: TextStyle(fontSize: 10, color: textColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left - tp.width - 4, y - tp.height / 2));
    }
    if (times.length < 2) return;
    final t0 = times.first;
    final span = math.max(times.last - t0, 1);
    for (final (values, color) in series) {
      final n = math.min(times.length, values.length);
      if (n < 2) continue;
      final path = Path();
      for (var i = 0; i < n; i++) {
        final x = left + (times[i] - t0) / span * w;
        final y = mapY(values[i]);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}
