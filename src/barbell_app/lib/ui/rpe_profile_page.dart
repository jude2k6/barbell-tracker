import 'package:flutter/material.dart';

import '../workout/rpe_profile.dart';
import '../workout/session.dart';
import 'app_scope.dart';
import 'app_theme.dart';
import 'app_widgets.dart';
import 'charts/rpe_profile_chart.dart';
import 'format.dart';

/// Every RPE tag for one exercise, grouped by RPE, with edit and remove.
/// Port of Stance's `RpeProfileManagerSheet` (headline title with a Done
/// pill, gray subtitle, Sort by tabs, RPE-coloured group headers and
/// card rows with Edit and Delete pills).
class RpeProfilePage extends StatefulWidget {
  const RpeProfilePage({
    super.key,
    required this.exerciseId,
    required this.exerciseTitle,
  });

  final String exerciseId;
  final String exerciseTitle;

  @override
  State<RpeProfilePage> createState() => _RpeProfilePageState();
}

class _RpeProfilePageState extends State<RpeProfilePage> {
  List<Session>? _sessions;
  RpeProfileSort _sort = RpeProfileSort.date;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sessions == null) _reload();
  }

  Future<void> _reload() async {
    final all = await AppScope.of(context).sessions.list();
    if (mounted) setState(() => _sessions = all);
  }

  /// Applies [change] to the row's set and saves its session.
  Future<void> _update(
      RpeProfileRow row, SetRecord Function(SetRecord) change) async {
    final store = AppScope.of(context).sessions;
    final session = await store.load(row.sessionId);
    if (session == null) return;
    final set = session.sets.where((s) => s.id == row.setId).firstOrNull;
    if (set == null) return;
    await store.save(session.replaceSet(change(set)));
    await _reload();
  }

  Future<void> _edit(RpeProfileRow row) async {
    final rpe = await showDialog<double>(
      context: context,
      builder: (_) => _EditRpeDialog(initial: row.rpe),
    );
    if (rpe == null || rpe == row.rpe) return;
    await _update(row, (s) => s.copyWith(rpe: rpe));
  }

  Future<void> _delete(RpeProfileRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this RPE tag?'),
        content: const Text(
            'This removes the RPE tag from the set. You can always add it again later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await _update(row, (s) => s.copyWith(clearRpe: true));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = _sessions;
    final groups = sessions == null
        ? const <RpeProfileGroup>[]
        : buildRpeGroups(sessions, exerciseId: widget.exerciseId, sort: _sort);
    final profile = sessions == null
        ? null
        : buildRpeProfile(sessions, exerciseId: widget.exerciseId);

    return Scaffold(
      body: SafeArea(
        child: sessions == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Row(children: [
                    Expanded(
                        child: Text('Edit RPE Profile',
                            style: theme.textTheme.headlineLarge)),
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 14),
                      child: AppSmallButton('Done',
                          onPressed: () => Navigator.of(context).pop()),
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                        'Review and clean up every RPE tag for this exercise.',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: AppColors.subtitleGray)),
                  ),
                  const SizedBox(height: 4),
                  Text(widget.exerciseTitle,
                      style: theme.textTheme.titleMedium),
                  if (profile != null && !profile.isEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Speed-intensity profile',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    RpeProfileChart(profile: profile),
                  ],
                  const SizedBox(height: 12),
                  if (groups.isEmpty)
                    Container(
                      height: 240,
                      alignment: Alignment.center,
                      child: Text('No RPE tags for this exercise yet',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: AppColors.subtitleGray)),
                    )
                  else ...[
                    Row(spacing: 8, children: [
                      Text('Sort by',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: AppColors.subtitleGray)),
                      Expanded(
                        child: AppSegmentedTabs<RpeProfileSort>(
                          values: RpeProfileSort.values,
                          selected: _sort,
                          label: (s) => s.label,
                          onSelect: (s) => setState(() => _sort = s),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Text('RPE ${fmtRpe(g.rpe)}',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: rpeColor(g.rpe))),
                      ),
                      for (final row in g.rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _row(theme, row),
                        ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }

  /// Stance's `RpeProfileRowView`: a card with the summary line and the
  /// Edit and Delete pills.
  Widget _row(ThemeData theme, RpeProfileRow row) => Container(
        key: ValueKey('rpeRow-${row.setId}'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: AppColors.cardFill,
            borderRadius: BorderRadius.circular(16)),
        child: Row(spacing: 8, children: [
          Expanded(
            child: Text(
              [
                fmtShortDate(row.date),
                fmtWeight(row.weight, row.unit),
                if (row.lastRepSpeed != null)
                  '${fmtVelocity(row.lastRepSpeed)} m/s',
              ].join(' · '),
              maxLines: 1,
              style: theme.textTheme.labelSmall.tabular,
            ),
          ),
          AppSmallButton('Edit', secondary: true, onPressed: () => _edit(row)),
          AppSmallButton('Delete', secondary: true, onPressed: () => _delete(row)),
        ]),
      );
}

class _EditRpeDialog extends StatefulWidget {
  const _EditRpeDialog({required this.initial});
  final double initial;

  @override
  State<_EditRpeDialog> createState() => _EditRpeDialogState();
}

class _EditRpeDialogState extends State<_EditRpeDialog> {
  late double _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit RPE', style: Theme.of(context).textTheme.headlineMedium),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Adjust the RPE for this set.'),
        const SizedBox(height: 12),
        Text(fmtRpe(_value),
            style: Theme.of(context).textTheme.headlineSmall.tabular),
        Slider(
          value: _value,
          min: 5,
          max: 10,
          divisions: 10,
          label: fmtRpe(_value),
          onChanged: (v) => setState(() => _value = v),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _value),
            child: const Text('Save')),
      ],
    );
  }
}
