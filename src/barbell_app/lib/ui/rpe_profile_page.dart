import 'package:flutter/material.dart';

import '../workout/rpe_profile.dart';
import '../workout/session.dart';
import 'app_scope.dart';
import 'app_theme.dart';
import 'app_widgets.dart';
import 'charts/rpe_profile_chart.dart';
import 'feedback_sheets.dart';
import 'format.dart';

/// Every RPE tag for one exercise, grouped by RPE, with edit and remove.
/// Port of Stance's `RpeProfileManagerSheet` (headline title with a Done
/// pill, gray subtitle, Sort by tabs, RPE-coloured group headers and
/// card rows with Edit and Delete pills) as a page on the sheet's
/// near-black background. Own additions: the exercise name and the
/// speed-intensity chart above the sort tabs.
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
    final rpe = await showEditRpeSheet(context, initial: row.rpe);
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
      backgroundColor: AppColors.sheetBackground,
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
                      padding: const EdgeInsets.only(left: 8),
                      child: AppSmallButton('Done',
                          onPressed: () => Navigator.of(context).pop()),
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                        'Review and clean up every RPE tag for this exercise.',
                        style: _body17(theme)),
                  ),
                  const SizedBox(height: 12),
                  Text(widget.exerciseTitle,
                      style: theme.textTheme.titleMedium),
                  if (profile != null && !profile.isEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: appCard(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Speed-Intensity Profile',
                              style: theme.textTheme.bodyLarge),
                          // No rated set to centre on: show RPE 5–10.
                          RpeProfileChart(
                              profile: profile, initiallyZoomedOut: true),
                        ],
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(spacing: 8, children: [
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
                  ),
                  if (groups.isEmpty)
                    Container(
                      height: 240,
                      alignment: Alignment.center,
                      child: Text('No RPE tags for this exercise yet',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: AppColors.subtitleGray)),
                    )
                  else
                    // Stance: 12 dp down, groups 20 dp apart, 8 dp
                    // between a group's header and rows.
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 20,
                        children: [
                          for (final g in groups)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: 8,
                              children: [
                                Text('RPE ${fmtRpe(g.rpe)}',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(color: rpeColor(g.rpe))),
                                for (final row in g.rows) _row(theme, row),
                              ],
                            ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// Stance's `RpeProfileRowView`: a `stanceCard` with 10 dp padding, the
  /// "weight · last-rep speed · date" line and the Edit and Delete pills.
  Widget _row(ThemeData theme, RpeProfileRow row) => Container(
        key: ValueKey('rpeRow-${row.setId}'),
        padding: const EdgeInsets.all(10),
        decoration: appCard(),
        child: Row(spacing: 8, children: [
          Expanded(
            child: Text(
              [
                fmtWeightIn(row.weight, row.unit, AppScope.weightUnitOf(context)),
                if (row.lastRepSpeed != null)
                  '${fmtVelocity(row.lastRepSpeed)} m/s',
                fmtShortDate(row.date),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall.tabular,
            ),
          ),
          AppSmallButton('Edit', secondary: true, onPressed: () => _edit(row)),
          AppSmallButton('Delete', secondary: true, onPressed: () => _delete(row)),
        ]),
      );
}

/// Stance's `StanceBody17Regular`: 17 sp regular on 24, SubtitleGray here.
TextStyle? _body17(ThemeData theme) => theme.textTheme.bodyLarge?.copyWith(
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w400,
    color: AppColors.subtitleGray);

/// Stance's `RpeProfileEditSheet`: "Edit RPE" (headlineLarge) with a Save
/// pill, the gray "Changes are saved automatically" subtitle and the RPE
/// slider card, on the near-black sheet. Save and dismissing both keep the
/// slider's value, as in Stance. Returns null only if never shown.
Future<double?> showEditRpeSheet(BuildContext context,
    {required double initial}) async {
  final value = ValueNotifier(initial);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: AppColors.sheetBackground,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    builder: (context) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                  child: Text('Edit RPE', style: theme.textTheme.headlineLarge)),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: AppSmallButton('Save',
                    key: const Key('rpeEditSave'),
                    onPressed: () => Navigator.of(context).pop()),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              child: Text(
                  'Adjust the RPE for this set. Changes are saved '
                  'automatically.',
                  style: _body17(theme)),
            ),
            ValueListenableBuilder(
              valueListenable: value,
              builder: (context, v, _) => RpeSliderCard(
                value: v,
                onChanged: (nv) => value.value = nv,
              ),
            ),
          ],
        ),
      );
    },
  );
  final result = value.value;
  value.dispose();
  return result;
}
