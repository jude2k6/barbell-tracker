import 'package:flutter/material.dart';

import '../workout/load_velocity.dart';
import '../workout/session.dart';
import '../workout/session_comparison.dart';
import '../workout/set_metrics.dart';
import 'charts/rep_velocity_chart.dart';
import 'format.dart';

/// Views of Stance's session comparison (notes §15).
enum ComparisonView {
  chart('Chart'),
  table('Table'),
  reps('Reps');

  const ComparisonView(this.label);
  final String label;
}

/// Set, type, weight, reps, speed and RPE for each set of one session.
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
    final theme = Theme.of(context);
    final head = theme.textTheme.labelMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final body = theme.textTheme.bodyMedium.tabular;

    Widget cell(String text, TextStyle? style, {int? setIndex}) => InkWell(
          onTap: setIndex == null || onSelect == null
              ? null
              : () => onSelect!(setIndex),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(text, style: style, textAlign: TextAlign.end),
          ),
        );

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
          horizontalInside:
              BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5)),
      children: [
        TableRow(children: [
          for (final h in [
            'Set',
            'Type',
            'Weight (${unit.name})',
            'Reps',
            'Speed (m/s)',
            'RPE',
          ])
            cell(h, head),
        ]),
        for (final r in rows)
          TableRow(
            decoration: r.setIndex == selectedSetIndex
                ? BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08))
                : null,
            children: [
              for (final t in [
                '${r.setIndex + 1}',
                r.type,
                fmtNumber(convertWeight(r.weight, r.unit, unit)),
                '${r.reps}',
                r.speed,
                r.rpe,
              ])
                cell(t, body, setIndex: r.setIndex),
            ],
          ),
      ],
    );
  }
}

/// Stance's "Reps" view: one small rep-speed chart per set of the session,
/// on a shared scale, scrolling sideways.
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
    if (session.sets.every((s) => s.reps.isEmpty)) {
      return Text('No comparisons for rep speed',
          style: theme.textTheme.bodySmall);
    }
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: session.sets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final set = session.sets[i];
          final selected = i == selectedSetIndex;
          return InkWell(
            onTap: () => onSelect(i),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 140,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    set.weight > 0
                        ? fmtWeight(set.weight, set.unit)
                        : 'Set ${i + 1}',
                    style: theme.textTheme.labelLarge,
                  ),
                  Text(fmtTime(set.startedAt),
                      style: theme.textTheme.labelSmall),
                  Expanded(
                    child: RepVelocityChart(
                      velocities: [for (final r in set.reps) r.meanVelocity],
                      bounds: bounds,
                      showAxes: false,
                      height: 100,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A set's rep speeds, optionally against another set of the session,
/// with max and average speed. Stance's rep chart and detail sheet.
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

    String setLabel(int i) {
      final o = s.sets[i];
      return o.weight > 0
          ? 'Set ${i + 1} · ${fmtWeight(o.weight, o.unit)}'
          : 'Set ${i + 1}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('Max speed ${fmtVelocity(set.reps.bestMeanVelocity)}',
            style: theme.textTheme.bodySmall.tabular),
        const SizedBox(width: 12),
        Text('Avg speed ${fmtVelocity(set.reps.avgMeanVelocity)}',
            style: theme.textTheme.bodySmall.tabular),
        const SizedBox(width: 12),
        // Long set labels must shrink rather than overflow the row.
        Expanded(
          child: options.isEmpty
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerRight,
                  child: DropdownButton<int?>(
                    isExpanded: true,
                    value: compare == null ? null : _compare,
                    hint: const Text('Compare', textAlign: TextAlign.end),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      for (final i in options)
                        DropdownMenuItem(
                            value: i,
                            child: Text(setLabel(i), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (i) => setState(() => _compare = i),
                  ),
                ),
        ),
      ]),
      RepVelocityChart(
        velocities: v,
        compare: [for (final r in compare?.reps ?? const <RepRecord>[]) r.meanVelocity],
      ),
      if (compare != null)
        Text('Second colour: ${setLabel(_compare!)}',
            style: theme.textTheme.labelSmall),
    ]);
  }
}
