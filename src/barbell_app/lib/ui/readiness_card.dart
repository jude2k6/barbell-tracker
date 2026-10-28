import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../workout/readiness.dart';
import '../workout/session.dart';
import 'app_scope.dart';
import 'app_theme.dart';
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

  /// Stance's `ReadinessColumn`: speed and unit, a 2 dp bar in the
  /// column's colour, then the label.
  Widget _stat(ThemeData theme, String label, double? v, Key key, Color bar,
      {required bool primary}) {
    final numberStyle = (primary
            ? theme.textTheme.headlineMedium
            : theme.textTheme.titleLarge)
        .tabular;
    return Expanded(
      flex: primary ? 130 : 90,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(v == null ? '--' : fmtVelocity(v),
                    key: key, maxLines: 1, style: numberStyle),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 3),
                child: Text('m/s', style: theme.textTheme.bodyMedium),
              ),
            ]),
        Container(
          height: 2,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
              color: bar, borderRadius: BorderRadius.circular(2)),
        ),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.subtitleGray)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            weightLabel: fmtWeightIn(set.weight, set.unit, AppScope.weightUnitOf(context)),
          );
    final grayMedium = theme.textTheme.bodyMedium
        ?.copyWith(color: AppColors.subtitleGray);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Readiness at ${fmtWeightIn(set.weight, set.unit, AppScope.weightUnitOf(context))} (m/s)',
                  style: theme.textTheme.bodyLarge),
            ),
            if (comparison != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ComparisonBanner(
                    comparison: comparison, textStyle: grayMedium),
              ),
            Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _stat(theme, 'This Session', current,
                      const Key('readinessThis'), AppColors.primary,
                      primary: true),
                  const SizedBox(width: 6),
                  _stat(theme, 'Last Session', r.lastSessionSpeed,
                      const Key('readinessLast'), AppColors.primaryLight,
                      primary: false),
                  const SizedBox(width: 6),
                  _stat(theme, 'Average', r.historicAverage,
                      const Key('readinessAvg'), AppColors.primaryVariant,
                      primary: false),
                ]),
            if (current != null && r.hasHistory) ...[
              const SizedBox(height: 12),
              ReadinessStrip(
                history: [for (final p in r.points) p.speed],
                current: current,
                lastSession: r.lastSessionSpeed,
                average: r.historicAverage,
              ),
            ],
            const SizedBox(height: 8),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
            if (!r.hasHistory)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No historical data available',
                    style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.subtitleGray,
                        fontStyle: FontStyle.italic)),
              ),
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
                    child: Row(spacing: 4, children: [
                      Text(fmtVelocity(p.speed),
                          style: theme.textTheme.bodyLarge.tabular),
                      Text('m/s', style: theme.textTheme.bodyMedium),
                      Text('(${daysAgoText(p.date, widget.now ?? DateTime.now())})',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.subtitleGray
                                  .withValues(alpha: 0.7))),
                      Expanded(
                        child: Text(
                          '${fmtDate(p.date)}'
                          '${p.sessionLabel.isEmpty ? '' : ' · ${p.sessionLabel}'}',
                          textAlign: TextAlign.end,
                          style: grayMedium,
                        ),
                      ),
                    ]),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Stance's `ComparisonBanner` / `readinessBannerChrome`: 16 dp radius,
/// 0xFF201B28 plus primary at 8 %, 1 dp pink-to-primary border; a purple
/// pill with the verdict, "Let's go!" when faster, then the description.
class _ComparisonBanner extends StatelessWidget {
  const _ComparisonBanner({required this.comparison, required this.textStyle});

  final ReadinessComparison comparison;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
            colors: [AppColors.pink, AppColors.primary]),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: Color.alphaBlend(
              AppColors.primary.withValues(alpha: 0.08),
              AppColors.fourgroundSolid),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(spacing: 8, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.purple2.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
                    Icon(
                        comparison.isFaster
                            ? Icons.bolt
                            : Icons.hourglass_bottom,
                        size: 14,
                        color: AppColors.purple1),
                    Text(comparison.title,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.purple1)),
                  ]),
                ),
                if (comparison.isFaster)
                  Text("Let's go!",
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 8),
              Container(
                key: const Key('readinessComparison'),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0x0AFFFFFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(comparison.description, style: textStyle),
              ),
            ]),
      ),
    );
  }
}

/// Stance's `ReadinessSpeedStripChart`: earlier sessions as thin grey marks, the average
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
    final values = [
      ...history,
      for (final v in [current, lastSession, average])
        if (v != null && v > 0) v,
    ].map(_round2).toList();
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
        color: AppColors.subtitleGray,
        fontWeight: FontWeight.w500,
        fontFeatures: tabularFigures);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 30,
        child: CustomPaint(
          painter: _StripPainter(
            lo: lo,
            span: hi - lo > 0 ? hi - lo : 0.1,
            history: history,
            current: current,
            lastSession: lastSession,
            average: average,
            track: Colors.white.withValues(alpha: 0.04),
            historyColor: AppColors.gray,
            averageColor: AppColors.primaryVariant,
            lastColor: AppColors.primaryLight,
            currentColor: AppColors.primary,
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
