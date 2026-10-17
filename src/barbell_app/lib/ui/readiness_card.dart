import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../workout/readiness.dart';
import '../workout/session.dart';
import 'format.dart';

/// This set's speed against last session and the average at the same
/// weight, with a Faster/Slower verdict, a speed strip and the history.
/// Port of Stance's readiness mini card and detail sheet.
class ReadinessCard extends StatefulWidget {
  const ReadinessCard({
    super.key,
    required this.result,
    required this.set,
    this.now,
  });

  final ReadinessResult result;

  /// The set being judged.
  final SetRecord set;

  /// Reference time for "days ago" labels; defaults to now.
  final DateTime? now;

  @override
  State<ReadinessCard> createState() => _ReadinessCardState();
}

class _ReadinessCardState extends State<ReadinessCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = widget.result;
    final set = widget.set;
    final current = readinessSpeed(set);
    final comparison = current == null
        ? null
        : compareReadiness(
            current: current,
            lastSession: r.lastSessionSpeed,
            average: r.historicAverage,
            setType: set.setType,
            weightLabel: fmtWeight(set.weight, set.unit),
          );
    final numberStyle = theme.textTheme.titleMedium.tabular;

    Widget stat(String label, double? v, Key key) => Expanded(
          child: Column(children: [
            Text(v == null ? '--' : fmtVelocity(v), key: key, style: numberStyle),
            Text(label, style: theme.textTheme.labelSmall),
          ]),
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Readiness at ${fmtWeight(set.weight, set.unit)} (m/s)',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(children: [
              stat('This Session', current, const Key('readinessThis')),
              stat('Last Session', r.lastSessionSpeed,
                  const Key('readinessLast')),
              stat('Average', r.historicAverage, const Key('readinessAvg')),
            ]),
            if (!r.hasHistory) ...[
              const SizedBox(height: 8),
              Text('No historical data available',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            if (comparison != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(
                  comparison.isFaster
                      ? Icons.trending_up
                      : Icons.trending_down,
                  color: comparison.isFaster ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    key: const Key('readinessComparison'),
                    TextSpan(children: [
                      TextSpan(
                          text: '${comparison.title}. ',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: comparison.description),
                    ]),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ]),
            ],
            if (current != null && r.hasHistory) ...[
              const SizedBox(height: 12),
              ReadinessStrip(
                history: [for (final p in r.points) p.speed],
                current: current,
                lastSession: r.lastSessionSpeed,
                average: r.historicAverage,
              ),
            ],
            if (r.points.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'See less' : 'See More'),
                ),
              ),
              if (_expanded)
                for (final p in r.points)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          '${daysAgoText(p.date, widget.now ?? DateTime.now())}'
                          ' · ${fmtDate(p.date)}'
                          '${p.sessionLabel.isEmpty ? '' : ' · ${p.sessionLabel}'}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Text('${fmtVelocity(p.speed)} m/s',
                          style: theme.textTheme.bodySmall.tabular),
                    ]),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Stance's speed strip: earlier sessions as thin grey marks, the average
/// as a dashed line, last session and this set as wider bars.
class ReadinessStrip extends StatelessWidget {
  const ReadinessStrip({
    super.key,
    required this.history,
    required this.current,
    this.lastSession,
    this.average,
  });

  final List<double> history;
  final double current;
  final double? lastSession, average;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final values = [
      ...history,
      for (final v in [current, lastSession, average])
        if (v != null && v > 0) v,
    ].map(_round2).toList();
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final labelStyle = theme.textTheme.labelSmall
        ?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: tabularFigures);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 40,
        child: CustomPaint(
          painter: _StripPainter(
            lo: lo,
            span: hi - lo > 0 ? hi - lo : 0.1,
            history: history,
            current: current,
            lastSession: lastSession,
            average: average,
            track: scheme.onSurface.withValues(alpha: 0.04),
            historyColor: Colors.grey,
            averageColor: scheme.primary.withValues(alpha: 0.7),
            lastColor: scheme.primary.withValues(alpha: 0.5),
            currentColor: scheme.primary,
          ),
          child: const SizedBox.expand(),
        ),
      ),
      Row(children: [
        Text(lo.toStringAsFixed(2), style: labelStyle),
        const Spacer(),
        Text(hi.toStringAsFixed(2), style: labelStyle),
      ]),
    ]);
  }
}

double _round2(double v) => (v * 100).round() / 100;

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.lo,
    required this.span,
    required this.history,
    required this.current,
    required this.lastSession,
    required this.average,
    required this.track,
    required this.historyColor,
    required this.averageColor,
    required this.lastColor,
    required this.currentColor,
  });

  final double lo, span;
  final List<double> history;
  final double current;
  final double? lastSession, average;
  final Color track, historyColor, averageColor, lastColor, currentColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Inset by half the widest bar so edge values stay fully visible.
    const inset = 3.0;
    final w = size.width - 2 * inset;
    double x(double v) => inset + (_round2(v) - lo) / span * w;

    canvas.drawRect(
        Rect.fromLTWH(0, (size.height - 24) / 2, size.width, 24),
        Paint()..color = track);

    void bar(double v, Color c, double width) => canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x(v) - width / 2, 0, width, size.height),
            Radius.circular(width / 2),
          ),
          Paint()..color = c,
        );

    for (final v in history) {
      bar(v, historyColor, 2);
    }
    final avg = average;
    if (avg != null && avg > 0) {
      final p = Paint()
        ..color = averageColor
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      for (var y = 0.0; y < size.height; y += 12) {
        canvas.drawLine(Offset(x(avg), y),
            Offset(x(avg), math.min(y + 4, size.height)), p);
      }
    }
    final last = lastSession;
    if (last != null && last > 0) bar(last, lastColor, 4);
    bar(current, currentColor, 6);
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.history != history ||
      old.current != current ||
      old.lastSession != lastSession ||
      old.average != average ||
      old.currentColor != currentColor;
}
