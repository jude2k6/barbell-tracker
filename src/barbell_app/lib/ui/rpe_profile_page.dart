import 'package:flutter/material.dart';

import '../workout/rpe_profile.dart';
import '../workout/session.dart';
import 'app_scope.dart';
import 'charts/rpe_profile_chart.dart';
import 'format.dart';

/// Every RPE tag for one exercise, grouped by RPE, with edit and remove.
/// Port of Stance's RPE profile manager sheet.
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
      appBar: AppBar(title: const Text('Edit RPE profile')),
      body: sessions == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(widget.exerciseTitle, style: theme.textTheme.titleMedium),
                Text('Review and clean up every RPE tag for this exercise.',
                    style: theme.textTheme.bodySmall),
                if (profile != null && !profile.isEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Speed-intensity profile',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  RpeProfileChart(profile: profile),
                ],
                const SizedBox(height: 16),
                if (groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: Text('No RPE tags for this exercise yet')),
                  )
                else ...[
                  Row(children: [
                    Text('Sort by', style: theme.textTheme.labelLarge),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<RpeProfileSort>(
                        segments: [
                          for (final s in RpeProfileSort.values)
                            ButtonSegment(value: s, label: Text(s.label)),
                        ],
                        selected: {_sort},
                        showSelectedIcon: false,
                        onSelectionChanged: (v) =>
                            setState(() => _sort = v.first),
                      ),
                    ),
                  ]),
                  for (final g in groups) ...[
                    const SizedBox(height: 16),
                    Row(children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: rpeColor(g.rpe),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('RPE ${fmtRpe(g.rpe)}',
                          style: theme.textTheme.titleSmall),
                    ]),
                    for (final row in g.rows)
                      ListTile(
                        key: ValueKey('rpeRow-${row.setId}'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          [
                            fmtShortDate(row.date),
                            fmtWeight(row.weight, row.unit),
                            if (row.lastRepSpeed != null)
                              '${fmtVelocity(row.lastRepSpeed)} m/s',
                          ].join(' · '),
                          style: theme.textTheme.bodyMedium.tabular,
                        ),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(row),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(row),
                          ),
                        ]),
                      ),
                  ],
                ],
              ],
            ),
    );
  }
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
      title: const Text('Edit RPE'),
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
