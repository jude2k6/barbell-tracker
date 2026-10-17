import 'package:flutter/material.dart';

import '../workout/session.dart';
import '../workout/set_metrics.dart';
import 'charts/sticking_bar.dart';
import 'comparison_views.dart';
import 'format.dart';
import 'stance_theme.dart';

/// Per-rep numbers: rep #, mean and peak velocity (m/s), ROM (cm), in
/// Stance's `RepSpeedDetailsTable` panel (#232323, 8 dp corners, 12 dp
/// padding). Stance collapses it under "View Details"; here it is open,
/// with ROM added. The fastest rep by mean velocity is emphasised.
class RepTable extends StatelessWidget {
  const RepTable({super.key, required this.reps});

  final List<RepRecord> reps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final head = theme.textTheme.bodyMedium
        ?.copyWith(color: StanceColors.subtitleGray);
    final body = theme.textTheme.bodyMedium.tabular;
    final best = reps.bestMeanVelocity;

    TableRow row(List<String> cells, TextStyle? style) => TableRow(children: [
          for (var i = 0; i < cells.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(cells[i],
                  style: style,
                  textAlign: i == 0 ? TextAlign.start : TextAlign.end),
            ),
        ]);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: detailPanelFill, borderRadius: BorderRadius.circular(8)),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(0.7)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          row(['Rep', 'Mean m/s', 'Peak m/s', 'ROM cm'], head),
          for (final r in reps)
            row(
              [
                '${r.index}',
                fmtVelocity(r.meanVelocity),
                fmtVelocity(r.peakVelocity),
                fmtRomCm(r.romMeters),
              ],
              r.meanVelocity == best && reps.length > 1
                  ? body?.copyWith(fontWeight: FontWeight.w700)
                  : body,
            ),
        ],
      ),
    );
  }
}

/// One [StickingBar] per rep that has a sticking region, with a legend.
class StickingList extends StatelessWidget {
  const StickingList({super.key, required this.reps});

  final List<RepRecord> reps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall.tabular;
    final label = theme.textTheme.labelSmall
        ?.copyWith(color: StanceColors.subtitleGray, fontWeight: FontWeight.w500);
    final withSticking = reps.where((r) => r.sticking != null).toList();
    if (withSticking.isEmpty) return const SizedBox.shrink();

    Widget legend(Color c, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, color: c),
            const SizedBox(width: 4),
            Text(text, style: label),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 12, runSpacing: 4, children: [
          legend(stickingOrange, '< 75 % of peak'),
          legend(stickingRed, '< 32.5 %'),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 2, height: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text('sticking point', style: label),
          ]),
        ]),
        const SizedBox(height: 8),
        for (final r in withSticking)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 48, child: Text('Rep ${r.index}', style: small)),
              Expanded(child: StickingBar(sticking: r.sticking!)),
              SizedBox(
                width: 48,
                child: Text(
                  r.sticking!.minVelocityPct == null
                      ? ''
                      : '${r.sticking!.minVelocityPct!.round()} %',
                  style: small,
                  textAlign: TextAlign.end,
                ),
              ),
            ]),
          ),
        Text('0 % = bottom, 100 % = lockout',
            style: label),
      ],
    );
  }
}
