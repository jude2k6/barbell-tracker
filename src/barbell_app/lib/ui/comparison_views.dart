import 'package:flutter/material.dart';

import '../workout/load_velocity.dart';
import '../workout/session.dart';
import '../workout/session_comparison.dart';
import '../workout/set_metrics.dart';
import 'app_theme.dart';
import 'app_widgets.dart';
import 'charts/rep_velocity_chart.dart';
import 'charts/rpe_profile_chart.dart';
import 'format.dart';

/// Views of Stance's session comparison (notes §15).
enum ComparisonView {
  chart('Chart'),
  table('Table'),
  reps('Reps');

  const ComparisonView(this.label);
  final String label;
}

/// Stance's RPE value in a [color] at 10 % chip (comparison table cell).
class _RpeTag extends StatelessWidget {
  const _RpeTag(this.text, this.style);

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final rpe = double.tryParse(text);
    final color = (rpe == null ? null : rpeColor(rpe)) ?? Colors.white;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: rpe == null ? Colors.transparent : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: style?.copyWith(color: color), maxLines: 1),
      ),
    );
  }
}

/// Column flex of Stance's `SessionComparisonTable`: weight 1, reps 0.45,
/// type 0.45, RPE 0.4, speed 1.
const _tableFlex = [100, 45, 45, 40, 100];

/// Stance's `SessionComparisonTableHeaders`: gray labelSmall headers above
/// both session blocks.
class ComparisonTableHeaders extends StatelessWidget {
  const ComparisonTableHeaders({super.key, required this.unit});

  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: AppColors.gray, fontWeight: FontWeight.w700);
    final labels = ['Weight (${unit.name})', 'Reps', 'Type', 'RPE', 'Speed (m/s)'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        for (final (i, l) in labels.indexed)
          Expanded(
            flex: _tableFlex[i],
            child: Text(l, style: style, textAlign: TextAlign.center, maxLines: 1),
          ),
      ]),
    );
  }
}

/// Stance's `SessionComparisonTable`: one 6 dp rounded row per set
/// (weight, reps, type, RPE, speed), alternately white 2 %, the selected
/// set Primary 30 %.
class ComparisonTable extends StatelessWidget {
  const ComparisonTable({
    super.key,
    required this.rows,
    required this.unit,
    this.selectedSetIndex,
    this.onSelect,
  });

  final List<ComparisonTableRow> rows;
  final WeightUnit unit;
  final int? selectedSetIndex;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(fontWeight: FontWeight.w600, color: Colors.white)
        .tabular;
    return Column(children: [
      for (final (n, r) in rows.indexed)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelect == null ? null : () => onSelect!(r.setIndex),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: r.setIndex == selectedSetIndex
                  ? const Color(0x4D792EFF)
                  : n.isEven
                      ? const Color(0x05FFFFFF)
                      : Colors.transparent,
            ),
            child: Row(children: [
              for (final (i, t) in [
                fmtNumber(convertWeight(r.weight, r.unit, unit)),
                '${r.reps}',
                r.type,
                r.rpe,
                r.speed,
              ].indexed)
                Expanded(
                  flex: _tableFlex[i],
                  child: i == 3
                      ? _RpeTag(t, style)
                      : Text(t, style: style, textAlign: TextAlign.center, maxLines: 1),
                ),
            ]),
          ),
        ),
    ]);
  }
}

/// Stance's `RepSpeedComparisonRow`: a "m/s" axis column, then one small
/// rep-speed chart per set of the session (weight label, start time) on a
/// shared scale, scrolling sideways; the selected set is white 5 %.
class RepSpeedRow extends StatelessWidget {
  const RepSpeedRow({
    super.key,
    required this.session,
    required this.selectedSetIndex,
    required this.onSelect,
  });

  final Session session;
  final int selectedSetIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bounds = repSpeedBounds(session.sets);
    final label = theme.textTheme.labelSmall;
    final axis = label?.copyWith(
        color: AppColors.subtitleGray, fontWeight: FontWeight.w500);
    final (lo, hi) = bounds;
    return SizedBox(
      height: 250,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Stance's y axis: "m/s", then the top and bottom of the shared
        // range level with the charts' plot area (8 + 22 + 6 dp from the
        // top, 140 dp tall less the 6 dp insets).
        SizedBox(
          width: 40,
          child: Stack(children: [
            Positioned(top: 4, left: 0, child: Text('m/s', style: axis)),
            Positioned(
                top: 36 - 7, left: 0, child: Text(hi.toStringAsFixed(2), style: axis.tabular)),
            Positioned(
                top: 164 - 7, left: 0, child: Text(lo.toStringAsFixed(2), style: axis.tabular)),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: session.sets.length,
            itemBuilder: (context, i) {
              final set = session.sets[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  child: Container(
                    width: 116,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: i == selectedSetIndex
                          ? const Color(0x0DFFFFFF)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 22),
                        RepVelocityChart(
                          velocities: [for (final r in set.reps) r.meanVelocity],
                          bounds: bounds,
                          showAxes: false,
                          height: 140,
                        ),
                        const Spacer(),
                        Text(
                          set.weight > 0 ? fmtWeight(set.weight, set.unit) : 'Set ${i + 1}',
                          style: label?.copyWith(
                              color: Colors.white, fontWeight: FontWeight.w500),
                        ),
                        Text(fmtTime(set.startedAt),
                            style: label?.copyWith(
                                color: AppColors.subtitleGray,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Stance's rep speed detail body: "Reps" with the Compare picker, the rep
/// chart (optionally against another set of the session), then Max and
/// Avg speed cards.
class SetRepChart extends StatefulWidget {
  const SetRepChart({super.key, required this.session, required this.setIndex});

  final Session session;
  final int setIndex;

  @override
  State<SetRepChart> createState() => _SetRepChartState();
}

class _SetRepChartState extends State<SetRepChart> {
  int? _compare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.session;
    final set = s.sets[widget.setIndex];
    final options = compareSetOptions(s, widget.setIndex);
    final compare = _compare != null && options.contains(_compare)
        ? s.sets[_compare!]
        : null;
    final v = [for (final r in set.reps) r.meanVelocity];

    String setLabel(int? i) {
      if (i == null) return 'None';
      final o = s.sets[i];
      return o.weight > 0
          ? 'Set ${i + 1} · ${fmtWeight(o.weight, o.unit)}'
          : 'Set ${i + 1}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Reps', style: theme.textTheme.bodyLarge),
      if (options.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            Text('Compare',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.subtitleGray)),
            const SizedBox(width: 8),
            Flexible(
              child: AppMenuPicker<int?>(
                key: const Key('compareSetPicker'),
                value: compare == null ? null : _compare,
                values: [null, ...options],
                label: setLabel,
                onChanged: (i) => setState(() => _compare = i),
              ),
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: RepVelocityChart(
          velocities: v,
          compare: [for (final r in compare?.reps ?? const <RepRecord>[]) r.meanVelocity],
          height: 226,
        ),
      ),
      Row(children: [
        Expanded(
            child: _SpeedStat('Max speed',
                '${fmtVelocity(set.reps.bestMeanVelocity)} m/s')),
        const SizedBox(width: 16),
        Expanded(
            child: _SpeedStat('Avg speed',
                '${fmtVelocity(set.reps.avgMeanVelocity)} m/s')),
      ]),
    ]);
  }
}

/// Stance's `SpeedStatCard`: a #232323 panel with the label and a speed
/// glyph over the value.
class _SpeedStat extends StatelessWidget {
  const _SpeedStat(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyLarge;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: detailPanelFill, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: body?.copyWith(color: AppColors.subtitleGray)),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.speed_outlined, size: 20, color: AppColors.subtitleGray),
          const SizedBox(width: 6),
          Text(value, style: body.tabular),
        ]),
      ]),
    );
  }
}

/// Stance's `DetailPanelFill` (rep speed detail panels).
const detailPanelFill = Color(0xFF232323);
