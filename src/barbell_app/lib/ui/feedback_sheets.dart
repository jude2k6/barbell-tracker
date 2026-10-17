import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analysis/exercises.dart';
import '../workout/load_velocity.dart';
import '../workout/readiness.dart';
import '../workout/rep_editing.dart';
import '../workout/rpe_profile.dart';
import '../workout/session.dart';
import 'charts/rpe_profile_chart.dart';
import 'charts/velocity_chart.dart';
import 'charts/weight_history_chart.dart';
import 'comparison_views.dart';
import 'format.dart';
import 'readiness_card.dart';
import 'rep_table.dart';

/// The modal sheets opened from the session feedback page's set cards
/// (Stance's readiness detail, RPE, rep speed detail and Edit Set sheets).

Future<T?> _sheet<T>(BuildContext context, String title, WidgetBuilder body) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
              16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            body(context),
          ],
        ),
      ),
    );

Future<void> showReadinessSheet(
        BuildContext context, ReadinessResult result, SetRecord set) =>
    _sheet(context, 'Readiness',
        (_) => ReadinessCard(result: result, set: set));

/// Stance's TutorialSheet for the weight performance chart: a sheet with
/// the title, subtitle and the tutorial image.
Future<void> showWeightPerformanceTutorial(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Weight Performance', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                    'Compare recent sets at any weight as an indicator of '
                    'progress.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                Image.asset('assets/images/weight_performance_tutorial.webp',
                    key: const Key('weightPerformanceTutorialImage')),
              ]),
        );
      },
    );

/// Stance's rep speed detail: the set's rep speeds (optionally against
/// another set), the velocity trace, per-rep table and sticking regions,
/// and same-weight history. Plus our analysis details.
Future<void> showRepSpeedSheet(BuildContext context,
    {required Session session,
    required int setIndex,
    required List<Session> all}) {
  final set = session.sets[setIndex];
  final history = set.weight > 0
      ? buildWeightHistory(all,
          exerciseId: session.exerciseId, weight: set.weight, unit: set.unit)
      : const <WeightHistoryPoint>[];
  return _sheet(context, 'Rep speed', (context) {
    final theme = Theme.of(context);
    final reps = set.reps;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (reps.isEmpty)
        const Text('No reps detected for this set.')
      else ...[
        SetRepChart(session: session, setIndex: setIndex),
        if (set.velocityTrace.length > 1 && set.traceHz != null) ...[
          const SizedBox(height: 16),
          Text('Velocity (m/s)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          VelocityChart(
            velocity: set.velocityTrace,
            hz: set.traceHz!,
            reps: [for (final r in reps) RepWindow(r.index, r.startSec, r.endSec)],
          ),
        ],
        const SizedBox(height: 16),
        RepTable(reps: reps),
        if (reps.any((r) => r.sticking != null)) ...[
          const SizedBox(height: 16),
          Text('Sticking region', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          StickingList(reps: reps),
        ],
      ],
      if (set.weight > 0) ...[
        const SizedBox(height: 16),
        Text('Sets at ${fmtWeight(set.weight, set.unit)}: '
            'slowest to fastest rep (m/s)',
            style: theme.textTheme.titleSmall),
        // Stance's "How do I use this?" button (always shown, not once-only).
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('weightPerformanceHelp'),
            onPressed: () => showWeightPerformanceTutorial(context),
            icon: const Icon(Icons.help_outline, size: 18),
            label: const Text('How do I use this?'),
          ),
        ),
        if (history.isNotEmpty) WeightHistoryChart(points: history),
      ],
      const SizedBox(height: 16),
      if (set.pipeline != null)
        Text(
          '${pipelineLabel(set.pipeline!)}'
          '${set.measuredHz == null ? '' : ' · ${set.measuredHz!.toStringAsFixed(0)} Hz'}',
          key: const Key('pipelineLabel'),
          style: theme.textTheme.labelMedium.tabular,
        ),
      for (final w in set.warnings) Text(w, style: theme.textTheme.bodySmall),
      if (set.rawCsvFile != null)
        Text('Raw: ${set.rawCsvFile}',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  });
}

/// What the RPE sheet returns: a new RPE, or null to clear it.
class RpeChoice {
  const RpeChoice(this.rpe);
  final double? rpe;
}

/// Stance's RPE sheet: "What RPE was the set?", a 5–10 slider in half
/// steps, Save / Clear, and the speed-intensity profile around this set's
/// last rep. Returns null when dismissed without a choice.
Future<RpeChoice?> showRpeSheet(
  BuildContext context, {
  required SetRecord set,
  RpeIntensityProfile? profile,
  VoidCallback? onEditProfile,
}) =>
    _sheet<RpeChoice>(context, 'RPE',
        (_) => _RpeEditor(set: set, profile: profile, onEditProfile: onEditProfile));

class _RpeEditor extends StatefulWidget {
  const _RpeEditor({required this.set, this.profile, this.onEditProfile});

  final SetRecord set;
  final RpeIntensityProfile? profile;
  final VoidCallback? onEditProfile;

  @override
  State<_RpeEditor> createState() => _RpeEditorState();
}

class _RpeEditorState extends State<_RpeEditor> {
  static const _defaultRpe = 8.0;
  late double _rpe = widget.set.rpe ?? _defaultRpe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = widget.profile;
    final speed = profile?.lastRepSpeed;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Enter your Rate of Perceived Exertion for this set. Last rep is '
          'the best indicator of your RPE.',
          style: theme.textTheme.bodyMedium),
      const SizedBox(height: 12),
      Text('What RPE was the set?', style: theme.textTheme.titleSmall),
      Row(children: [
        Expanded(
          child: Slider(
            key: const Key('rpeSlider'),
            value: _rpe,
            min: 5,
            max: 10,
            divisions: 10,
            label: fmtRpe(_rpe),
            activeColor: rpeColor(_rpe),
            onChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() => _rpe = v);
            },
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(fmtRpe(_rpe),
              key: const Key('rpeValue'),
              textAlign: TextAlign.end,
              style: theme.textTheme.titleLarge.tabular),
        ),
      ]),
      if (profile != null && profile.hasSuggestion && speed != null)
        Text(
          'Past sets with a last rep near ${fmtVelocity(speed)} m/s: '
          'RPE ${fmtRpe(profile.minRpe) == fmtRpe(profile.maxRpe) ? fmtRpe(profile.minRpe) : '${fmtRpe(profile.minRpe)}–${fmtRpe(profile.maxRpe)}'}',
          key: const Key('rpeSuggestion'),
          style: theme.textTheme.bodyMedium.tabular,
        ),
      const SizedBox(height: 12),
      Row(children: [
        if (widget.set.rpe != null)
          TextButton(
            key: const Key('rpeClear'),
            onPressed: () => Navigator.of(context).pop(const RpeChoice(null)),
            child: const Text('Clear'),
          ),
        const Spacer(),
        FilledButton(
          key: const Key('rpeSave'),
          onPressed: () => Navigator.of(context).pop(RpeChoice(_rpe)),
          child: const Text('Save'),
        ),
      ]),
      if (profile != null && !profile.isEmpty) ...[
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: Text('Speed-Intensity Profile',
                  style: theme.textTheme.titleSmall)),
          if (widget.onEditProfile != null)
            TextButton(
              onPressed: widget.onEditProfile,
              child: const Text('Edit Profile'),
            ),
        ]),
        RpeProfileChart(profile: profile),
      ],
    ]);
  }
}

/// What the Edit Set sheet returns. Rep edits are saved as they happen
/// (through the sheet's callbacks), as in Stance.
sealed class SetEdit {
  const SetEdit();
}

class SetEdited extends SetEdit {
  const SetEdited(this.set);
  final SetRecord set;
}

class SetDeleted extends SetEdit {
  const SetDeleted();
}

/// Stance's Edit Set sheet (notes §17). Details: weight, set type, Copy
/// Set ID, Report Issue, Delete Set. Reps: the 7-day edit timer, total reps
/// with Recalculate, and Check Reps.
Future<SetEdit?> showEditSetSheet(
  BuildContext context, {
  required SetRecord set,
  required bool deadlift,
  required Future<SetRecord> Function(SetRecord set) onSave,
  required Future<SetRecord?> Function(SetRecord set) onCheckReps,
  required Future<SetRecord> Function(SetRecord set) onReportIssue,
  DateTime Function()? now,
}) =>
    _sheet<SetEdit>(
      context,
      'Edit Set',
      (_) => _SetEditor(
        set: set,
        deadlift: deadlift,
        onSave: onSave,
        onCheckReps: onCheckReps,
        onReportIssue: onReportIssue,
        now: now ?? DateTime.now,
      ),
    );

class _SetEditor extends StatefulWidget {
  const _SetEditor({
    required this.set,
    required this.deadlift,
    required this.onSave,
    required this.onCheckReps,
    required this.onReportIssue,
    required this.now,
  });

  final SetRecord set;
  final bool deadlift;
  final Future<SetRecord> Function(SetRecord set) onSave;
  final Future<SetRecord?> Function(SetRecord set) onCheckReps;
  final Future<SetRecord> Function(SetRecord set) onReportIssue;
  final DateTime Function() now;

  @override
  State<_SetEditor> createState() => _SetEditorState();
}

class _SetEditorState extends State<_SetEditor> {
  late SetRecord _set = widget.set;
  late final _weight = TextEditingController(
      text: widget.set.weight > 0 ? fmtNumber(widget.set.weight) : '');
  late final _reps = TextEditingController(text: '${widget.set.reps.length}');
  late SetType? _setType = widget.set.setType;
  bool _details = true;
  bool _idCopied = false;
  bool _busy = false;

  Duration get _timeLeft => editTimeLeft(_set, widget.now());

  @override
  void initState() {
    super.initState();
    _reps.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  void _done() {
    final w = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    Navigator.of(context).pop(SetEdited(_set.copyWith(
      weight: w != null && w > 0 ? w : null,
      setType: _setType,
      clearSetType: _setType == null,
    )));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Set'),
        content: const Text('Are you sure you want to delete this set? '
            'This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('confirmDeleteSet'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop(const SetDeleted());
  }

  Future<void> _message(String title, String body) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );

  /// Rep edits need time left in the edit window and a velocity trace.
  Future<bool> _mayEditReps() async {
    if (_timeLeft == Duration.zero) {
      await _message('Edit Window Expired',
          'Sorry, you can no longer edit your reps. Sets can only be edited for 7 '
              'days after recording.');
      return false;
    }
    if (!canEditReps(_set)) {
      await _message('Error',
          "Rep editing isn't available for this set. Velocity data may not be "
              'available for older sets.');
      return false;
    }
    return true;
  }

  Future<void> _recalculate() async {
    if (!await _mayEditReps()) return;
    final desired = int.tryParse(_reps.text.trim()) ?? 0;
    switch (recalculateReps(_set, desired)) {
      case Recalculated(:final set):
        setState(() => _busy = true);
        final saved = await widget.onSave(set);
        if (!mounted) return;
        setState(() {
          _busy = false;
          _set = saved;
          _reps.text = '${saved.reps.length}';
        });
      case CanOnlyFindFewer():
        await _message(
            "Can't Find More Reps",
            widget.deadlift
                ? "Sorry, we can't find more reps."
                : "Sorry, we can't find more reps. You can manually add more reps "
                    'in the Check Reps view.');
        if (mounted) _reps.text = '${_set.reps.length}';
      case NoTrace():
        await _mayEditReps();
    }
  }

  Future<void> _checkReps() async {
    if (!await _mayEditReps()) return;
    final updated = await widget.onCheckReps(_set);
    if (updated != null && mounted) {
      setState(() {
        _set = updated;
        _reps.text = '${updated.reps.length}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Details')),
          ButtonSegment(value: false, label: Text('Reps', key: Key('repsTab'))),
        ],
        selected: {_details},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() => _details = v.first),
      ),
      const SizedBox(height: 16),
      if (_details) ..._detailsTab(theme) else ..._repsTab(theme),
      const SizedBox(height: 16),
      Row(children: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        const Spacer(),
        FilledButton(
            key: const Key('editDone'), onPressed: _done, child: const Text('Done')),
      ]),
    ]);
  }

  List<Widget> _detailsTab(ThemeData theme) => [
        TextField(
          key: const Key('editWeight'),
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: 'Weight',
            suffixText: _set.unit.name,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text('Set Type${_setType == null ? ' · Not set' : ''}',
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final t in SetType.values)
            ChoiceChip(
              label: Text(t.displayName),
              selected: _setType == t,
              onSelected: (on) => setState(() => _setType = on ? t : null),
            ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(
            key: const Key('copySetId'),
            icon: Icon(_idCopied ? Icons.check : Icons.copy),
            label: Text(_idCopied ? 'ID Copied' : 'Copy Set ID'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _set.id));
              if (mounted) setState(() => _idCopied = true);
            },
          ),
          OutlinedButton.icon(
            key: const Key('reportIssue'),
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Report Issue'),
            onPressed: () async {
              final updated = await widget.onReportIssue(_set);
              if (mounted) setState(() => _set = updated);
            },
          ),
          TextButton.icon(
            key: const Key('deleteSet'),
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete Set'),
          ),
        ]),
      ];

  List<Widget> _repsTab(ThemeData theme) {
    final left = _timeLeft;
    final current = _set.reps.length;
    final desired = int.tryParse(_reps.text.trim());
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          key: const Key('editTimer'),
          avatar: const Icon(Icons.timer_outlined, size: 18),
          label: Text(left == Duration.zero
              ? 'Edit Expired'
              : '${formatTimeLeft(left)} left to edit'),
        ),
      ),
      Text('You have 7 days to edit your reps after a set.',
          style: theme.textTheme.bodySmall),
      const SizedBox(height: 16),
      TextField(
        key: const Key('totalReps'),
        controller: _reps,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
            labelText: 'Total reps', border: OutlineInputBorder()),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text("If the rep count isn't correct then edit and tap recalculate.",
            style: theme.textTheme.bodySmall),
      ),
      if (_busy) const LinearProgressIndicator(),
      Wrap(spacing: 8, runSpacing: 4, children: [
        FilledButton(
          key: const Key('recalculate'),
          onPressed: _busy || desired == null || desired == current ? null : _recalculate,
          child: const Text('Recalculate'),
        ),
        OutlinedButton(
          key: const Key('checkReps'),
          onPressed: _busy ? null : _checkReps,
          child: const Text('Check Reps'),
        ),
      ]),
    ];
  }
}

/// What the Report Issue sheet returns: the new note, or null to delete it.
class NoteChange {
  const NoteChange(this.note);
  final String? note;
}

/// Stance's Report Issue sheet (notes §17): "Does the data look correct?"
/// and a note about what isn't. The note is the set's [SetRecord.note].
/// Returns null when closed without a change.
Future<NoteChange?> showReportIssueSheet(BuildContext context, String? note) =>
    _sheet<NoteChange>(context, 'Report Issue', (_) => _ReportIssue(note: note));

class _ReportIssue extends StatefulWidget {
  const _ReportIssue({this.note});
  final String? note;

  @override
  State<_ReportIssue> createState() => _ReportIssueState();
}

class _ReportIssueState extends State<_ReportIssue> {
  late bool _looksCorrect = widget.note == null;
  late final _text = TextEditingController(text: widget.note ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _text.text.trim();
    Navigator.of(context).pop(NoteChange(t.isEmpty ? null : t));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasNote = widget.note != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Feedback', style: theme.textTheme.titleSmall),
      Text('Does the data look correct?', style: theme.textTheme.bodyMedium),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        ChoiceChip(
          key: const Key('dataLooksCorrect'),
          label: const Text('Yes'),
          selected: _looksCorrect,
          onSelected: (_) => setState(() => _looksCorrect = true),
        ),
        ChoiceChip(
          key: const Key('dataLooksWrong'),
          label: const Text("No, something doesn't look right"),
          selected: !_looksCorrect,
          onSelected: (_) => setState(() => _looksCorrect = false),
        ),
      ]),
      const SizedBox(height: 16),
      Text('Notes', style: theme.textTheme.titleSmall),
      Text("Let us know what you think isn't looking right.",
          style: theme.textTheme.bodySmall),
      const SizedBox(height: 8),
      TextField(
        key: const Key('issueNote'),
        controller: _text,
        enabled: !_looksCorrect,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      Row(children: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        const Spacer(),
        if (hasNote && _looksCorrect)
          FilledButton(
            key: const Key('deleteNote'),
            onPressed: () => Navigator.of(context).pop(const NoteChange(null)),
            child: const Text('Delete note'),
          )
        else if (hasNote)
          FilledButton(
              key: const Key('updateNote'),
              onPressed: _submit,
              child: const Text('Update Note'))
        else
          FilledButton(
            key: const Key('addNote'),
            onPressed: _looksCorrect ? null : _submit,
            child: const Text('Add Note'),
          ),
      ]),
    ]);
  }
}
