import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sensor/orientation.dart';
import '../workout/sensor_diagnostics.dart';
import '../workout/stream_mode.dart';
import 'app_scope.dart';
import 'app_theme.dart';
import 'app_widgets.dart';
import 'sensor_status_chip.dart';
import 'workout_flow.dart';

/// Debug screen for the clock-mode questions in
/// notes/own-orientation-clock-mode.md: switch angles/clock mode live, see
/// what the phone actually receives per notification, compare the app's tilt
/// filter with the sensor's own fusion during reps, and tune its gains.
///
/// Not a Stance screen; it lives in the Debug Menu.
class SensorDiagnosticsPage extends StatefulWidget {
  const SensorDiagnosticsPage({super.key});

  @override
  State<SensorDiagnosticsPage> createState() => _SensorDiagnosticsPageState();
}

class _SensorDiagnosticsPageState extends State<SensorDiagnosticsPage> {
  SensorDiagnostics? _diag;
  late TiltGains _gains;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_diag != null) return;
    final app = AppScope.of(context);
    _gains = app.preferences?.value.tiltGains ?? const TiltGains();
    _diag = SensorDiagnostics(app.sensor, gains: _gains);
  }

  @override
  void dispose() {
    _diag?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
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
                        'Sensor diagnostics',
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
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([_diag, app.preferences]),
                builder: (context, _) => _content(context, _diag!),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, SensorDiagnostics d) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final caption = text.bodySmall?.copyWith(color: AppColors.subtitleGray);
    final c = d.comparison;
    final stats = d.linkStats;
    final gaps = stats?.gapsMs;
    final rate = app.sensor.rate;
    final traces = c.traces();
    // The connected sensor's mode, else the saved setting for the next one.
    final clock = d.hasWitLink
        ? d.clockMode
        : app.preferences?.value.clockMode ?? false;
    String f(double v, [int digits = 1]) => v.toStringAsFixed(digits);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (!app.sensor.isStreaming)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Device is not connected', style: text.bodySmall),
          ),
        _Section(
          title: 'Stream mode',
          children: [
            AppSegmentedTabs<bool>(
              values: const [false, true],
              selected: clock,
              label: (isClock) => isClock ? 'Clock' : 'Angles',
              keys: const {
                false: Key('modeAngles'),
                true: Key('modeClock'),
              },
              onSelect: (isClock) async {
                await setClockMode(app.preferences, app.sensor, isClock);
                d.reset();
              },
            ),
            const SizedBox(height: 8),
            Text(
              clock
                  ? 'Clock: the sensor sends its ms counter, the app works '
                      'out orientation. Kept for the next connect.'
                  : 'Angles: the sensor sends its own fused angles. The app\'s '
                      'filter runs alongside for comparison.',
              style: caption,
            ),
          ],
        ),
        _Section(
          title: 'What arrives',
          children: [
            _Row('Notifications/s', f(d.notificationsPerS, 0)),
            _Row('Samples/s', f(d.samplesPerS, 0)),
            _Row('Delivered rate', '${f(rate.hz, 0)} Hz'),
            _Row('MTU', '${stats?.mtu ?? '-'}'),
            _Row('Frames per notification',
                _histogram(stats?.framesPerNotification)),
            _Row('Notification bytes', _histogram(stats?.notificationLengths)),
            _Row(
              'Gap mean / p95 / max',
              gaps == null
                  ? '-'
                  : '${f(gaps.mean)} / ${f(gaps.p95)} / ${f(gaps.max)} ms',
            ),
            if (d.clockMode)
              _Row('Counter steps (ms)', _histogram(c.counterSteps)),
            _Row('Estimated missing',
                '${rate.estimatedMissing} (${f(rate.lossFraction * 100)} %)'),
            _Row('Skipped bytes', '${stats?.skippedBytes ?? '-'}'),
          ],
        ),
        _Section(
          title: 'App filter vs sensor',
          children: [
            if (!c.hasReference)
              Text(
                'No reference in clock mode: the samples already come from '
                'the app\'s filter. Switch to Angles to compare.',
                style: caption,
              )
            else ...[
              _Row('Tilt difference now', '${f(c.tiltDiffDeg, 2)}°'),
              _Row('Still, RMS', '${f(c.stillRmsDeg, 2)}°'),
            ],
            _Row('Gyro bias (still)',
                '${f(c.biasX, 2)}, ${f(c.biasY, 2)}, ${f(c.biasZ, 2)} °/s'),
            if (c.hasReference) ...[
              const SizedBox(height: 8),
              _TraceChart(
                label: 'Tilt difference (°)',
                series: [(traces.tilt, AppColors.amber)],
                minRange: 2,
                fromZero: true,
              ),
            ],
            const SizedBox(height: 8),
            _TraceChart(
              label: c.hasReference
                  ? 'Vertical acceleration (g): sensor vs app'
                  : 'Vertical acceleration (g)',
              series: [
                (traces.ref, AppColors.primaryVariant),
                if (c.hasReference) (traces.own, AppColors.pink),
              ],
              minRange: 0.5,
            ),
          ],
        ),
        _Section(
          title: 'Filter gains',
          children: [
            _GainSlider(
              label: 'kp',
              value: _gains.kp,
              min: 0,
              max: 10,
              onChanged: (v) => _setGains(_gains.copyWith(kp: v)),
              onChangeEnd: (_) => _saveGains(),
            ),
            _GainSlider(
              label: 'ki',
              value: _gains.ki,
              min: 0,
              max: 1,
              digits: 2,
              onChanged: (v) => _setGains(_gains.copyWith(ki: v)),
              onChangeEnd: (_) => _saveGains(),
            ),
            _GainSlider(
              label: 'Gate (g)',
              value: _gains.accelGate,
              min: 0.02,
              max: 0.5,
              digits: 2,
              onChanged: (v) => _setGains(_gains.copyWith(accelGate: v)),
              onChangeEnd: (_) => _saveGains(),
            ),
            Text(
              'Changes apply to the comparison now and, in clock mode, to '
              'the live stream. Higher kp lets bar acceleration leak into '
              'the tilt; lower recovers slower between reps.',
              style: caption,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: AppSmallButton(
                'Reset to defaults',
                secondary: true,
                onPressed: _gains == const TiltGains()
                    ? null
                    : () {
                        _setGains(const TiltGains());
                        _saveGains();
                      },
              ),
            ),
          ],
        ),
        _Section(
          title: 'Movements',
          children: [
            Text(
              c.movingS == null
                  ? 'Still. Do a rep; each one is listed here and logged.'
                  : 'Moving… ${f(c.movingS!)} s',
              style: caption,
            ),
            if (c.movements.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MovementTable(c.movements),
            ],
          ],
        ),
        FilledButton(
          key: const Key('diagnosticsReset'),
          onPressed: d.reset,
          child: const Text('Reset stats'),
        ),
      ],
    );
  }

  void _setGains(TiltGains g) {
    setState(() => _gains = g);
    _diag!.gains = g;
  }

  void _saveGains() {
    final app = AppScope.of(context);
    setTiltGains(app.preferences, app.sensor, _gains);
  }
}

/// "20:51 40:3" style, keys sorted, gaps (-1) shown as "gap".
String _histogram(Map<int, int>? m) {
  if (m == null || m.isEmpty) return '-';
  final keys = m.keys.toList()..sort();
  return keys.map((k) => '${k < 0 ? 'gap' : k}×${m[k]}').join('  ');
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardFill,
          border: Border.all(color: AppColors.cardStroke),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: style?.copyWith(color: AppColors.subtitleGray)),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Text(value, style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _GainSlider extends StatelessWidget {
  const _GainSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
    this.digits = 1,
  });

  final String label;
  final double value, min, max;
  final int digits;
  final ValueChanged<double> onChanged, onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        SizedBox(width: 64, child: Text(label, style: style)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(value.toStringAsFixed(digits),
              style: style, textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _MovementTable extends StatelessWidget {
  const _MovementTable(this.movements);

  final List<MovementResult> movements;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final head = style?.copyWith(color: AppColors.subtitleGray);
    String f(double? v, int digits) => v?.toStringAsFixed(digits) ?? '-';
    Widget cell(String s, TextStyle? st) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(s, style: st, textAlign: TextAlign.end),
        );
    return Table(
      columnWidths: const {0: FlexColumnWidth(1.1)},
      children: [
        TableRow(children: [
          for (final h in ['s', 'tilt pk°', 'tilt end°', 'v m/s', 'v err', 'd err cm'])
            cell(h, head),
        ]),
        for (final m in movements)
          TableRow(children: [
            cell(f(m.durationS, 2), style),
            cell(f(m.peakTiltDiffDeg, 1), style),
            cell(f(m.endTiltDiffDeg, 1), style),
            cell(f(m.peakVelocity, 2), style),
            cell(f(m.peakVelocityError, 3), style),
            cell(
                f(m.peakDisplacementError == null
                    ? null
                    : m.peakDisplacementError! * 100, 1),
                style),
          ]),
      ],
    );
  }
}

/// Small auto-ranging line chart of the last few seconds.
class _TraceChart extends StatelessWidget {
  const _TraceChart({
    required this.label,
    required this.series,
    required this.minRange,
    this.fromZero = false,
  });

  final String label;
  final List<(List<double>, Color)> series;

  /// Smallest half-range (or range, with [fromZero]) shown.
  final double minRange;
  final bool fromZero;

  @override
  Widget build(BuildContext context) {
    var peak = minRange;
    for (final (values, _) in series) {
      for (final v in values) {
        peak = math.max(peak, v.abs());
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        CustomPaint(
          size: const Size(double.infinity, 120),
          painter: _TracePainter(
            series: series,
            yMin: fromZero ? 0 : -peak,
            yMax: peak,
            gridColor: Theme.of(context).dividerColor,
            textColor: AppColors.subtitleGray,
          ),
        ),
      ],
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter({
    required this.series,
    required this.yMin,
    required this.yMax,
    required this.gridColor,
    required this.textColor,
  });

  static const left = 36.0;

  final List<(List<double>, Color)> series;
  final double yMin, yMax;
  final Color gridColor, textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - left;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    double mapY(double v) => (1 - (v - yMin) / (yMax - yMin)) * h;
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final v in [yMin, (yMin + yMax) / 2, yMax]) {
      final y = mapY(v);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      final tp = TextPainter(
        text: TextSpan(
          text: v.toStringAsFixed(yMax < 10 ? 1 : 0),
          style: TextStyle(fontSize: 10, color: textColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left - tp.width - 4,
          (y - tp.height / 2).clamp(0, h - tp.height)));
    }
    for (final (values, color) in series) {
      if (values.length < 2) continue;
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = left + i / (values.length - 1) * w;
        final y = mapY(values[i].clamp(yMin, yMax));
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_TracePainter old) => true;
}
