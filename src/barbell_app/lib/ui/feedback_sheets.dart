import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analysis/exercises.dart';
import '../workout/load_velocity.dart';
import '../workout/readiness.dart';
import '../workout/rep_editing.dart';
import '../workout/rpe_profile.dart';
import '../workout/session.dart';
import 'app_theme.dart';
import 'app_widgets.dart';
import 'charts/rpe_profile_chart.dart';
import 'charts/velocity_chart.dart';
import 'charts/weight_history_chart.dart';
import 'comparison_views.dart';
import 'format.dart';
import 'readiness_card.dart';
import 'rep_table.dart';

/// The modal sheets opened from the session feedback page's set cards
/// (Stance's readiness detail, RPE, rep speed detail and Edit Set sheets).

/// Stance's modal sheets: 30 dp top corners, the Material drag handle and
/// a dark fill ([color]; most are #201B28). The header is the [title] in
/// [titleStyle] (headlineMedium by default) with an optional [action]
/// button at the end.
Future<T?> _sheet<T>(
  BuildContext context,
  WidgetBuilder body, {
  String? title,
  TextStyle? Function(TextTheme)? titleStyle,
  WidgetBuilder? action,
  Color color = AppColors.fourgroundSolid,
  double padding = 16,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: color,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
              padding, 0, padding, 24 + MediaQuery.viewInsetsOf(context).bottom),
          children: [
            if (title != null) ...[
              Row(children: [
                Expanded(
                  child: Text(title,
                      style: (titleStyle ?? (t) => t.headlineMedium)(
                          Theme.of(context).textTheme)),
                ),
                if (action != null) action(context),
              ]),
              const SizedBox(height: 16),
            ],
            body(context),
          ],
        ),
      ),
    );

/// Section headings in the sheets (Stance's bodyLarge white).
TextStyle? _heading(BuildContext context) => Theme.of(context).textTheme.bodyLarge;

/// Secondary text in the sheets (SubtitleGray).
TextStyle? _subtitle(BuildContext context, [TextStyle? Function(TextTheme)? base]) =>
    (base ?? (t) => t.bodyMedium)(Theme.of(context).textTheme)
        ?.copyWith(color: AppColors.subtitleGray);

Future<void> showReadinessSheet(
        BuildContext context, ReadinessResult result, SetRecord set) =>
    _sheet(context, (_) => ReadinessCard(result: result, set: set),
        title: 'Readiness');

/// Stance's TutorialSheet for the weight performance chart: a sheet with
/// the title, subtitle and the tutorial image.
Future<void> showWeightPerformanceTutorial(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: AppColors.fourgroundSolid,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) {
        final theme = Theme.of(context);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Weight Performance', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                    'Compare recent sets at any weight as an indicator of '
                    'progress.',
                    style: _subtitle(context, (t) => t.bodyLarge)),
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
  // Stance's `RepSpeedDetailSheet`: no title, Secondary (#363536) fill,
  // 26 dp sides.
  return _sheet(color: AppColors.secondary, padding: 26, context, (context) {
    final theme = Theme.of(context);
    final reps = set.reps;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (reps.isEmpty)
        Text('No reps detected for this set.', style: _subtitle(context))
      else ...[
        SetRepChart(session: session, setIndex: setIndex),
        if (set.velocityTrace.length > 1 && set.traceHz != null) ...[
          const SizedBox(height: 16),
          Text('Velocity (m/s)', style: _heading(context)),
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
          Text('Sticking region', style: _heading(context)),
          const SizedBox(height: 8),
          StickingList(reps: reps),
        ],
      ],
      // Stance's `WeightPerformanceSection`.
      if (set.weight > 0) ...[
        const SizedBox(height: 24),
        Text('Comparison against previous Sets & Sessions at',
            style: _subtitle(context, (t) => t.bodyLarge)),
        const SizedBox(height: 6),
        Text(fmtWeight(set.weight, set.unit),
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 24),
        if (history.isNotEmpty) WeightHistoryChart(points: history, height: 226),
        const SizedBox(height: 16),
        // Stance's "How do I use this?" button (always shown, not once-only).
        Material(
          color: detailPanelFill,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('weightPerformanceHelp'),
            onTap: () => showWeightPerformanceTutorial(context),
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 20, color: AppColors.subtitleGray),
                  const SizedBox(width: 8),
                  Text('How do I use this?', style: _subtitle(context, (t) => t.bodyLarge)),
                  const Spacer(),
                  const Icon(Icons.arrow_forward, size: 20, color: Colors.white),
                ]),
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 24),
      if (set.pipeline != null)
        Text(
          '${pipelineLabel(set.pipeline!)}'
          '${set.measuredHz == null ? '' : ' · ${set.measuredHz!.toStringAsFixed(0)} Hz'}',
          key: const Key('pipelineLabel'),
          style: _subtitle(context, (t) => t.labelMedium).tabular,
        ),
      for (final w in set.warnings) Text(w, style: _subtitle(context, (t) => t.bodySmall)),
      if (set.rawCsvFile != null)
        Text('Raw: ${set.rawCsvFile}', style: _subtitle(context, (t) => t.bodySmall)),
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
    // Stance's `RpeDetailSheet` sits on its #101010 StanceBackground.
    _sheet<RpeChoice>(
      context,
      (_) => _RpeEditor(set: set, profile: profile, onEditProfile: onEditProfile),
      color: const Color(0xFF101010),
    );

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
      // Stance: "RPE" in headlineLarge with a small Save button.
      Row(children: [
        Expanded(child: Text('RPE', style: theme.textTheme.headlineLarge)),
        FilledButton(
          key: const Key('rpeSave'),
          style: appSmallButtonStyle(context),
          onPressed: () => Navigator.of(context).pop(RpeChoice(_rpe)),
          child: const Text('Save'),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
            'Enter your Rate of Perceived Exertion for this set. Last rep is '
            'the best indicator of your RPE',
            style: _subtitle(context, (t) => t.bodyLarge)),
      ),
      if (profile != null && !profile.isEmpty) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: appCard(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Speed-Intensity Profile', style: _heading(context)),
            RpeProfileChart(profile: profile),
            if (profile.hasSuggestion && speed != null)
              Text(
                'Past sets with a last rep near ${fmtVelocity(speed)} m/s: '
                'RPE ${fmtRpe(profile.minRpe) == fmtRpe(profile.maxRpe) ? fmtRpe(profile.minRpe) : '${fmtRpe(profile.minRpe)}–${fmtRpe(profile.maxRpe)}'}',
                key: const Key('rpeSuggestion'),
                style: _subtitle(context).tabular,
              ),
          ]),
        ),
      ],
      if (widget.onEditProfile != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              style: appSmallButtonStyle(context, secondary: true),
              onPressed: widget.onEditProfile,
              child: const Text('Edit Profile'),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: RpeSliderCard(
          value: _rpe,
          onChanged: (v) => setState(() => _rpe = v),
          onClear: widget.set.rpe == null
              ? null
              : () => Navigator.of(context).pop(const RpeChoice(null)),
        ),
      ),
    ]);
  }
}

/// Stance's `RpeSliderCard`: the value in its RPE colour over a white
/// slider with a Primary track (5–10 in half steps), Clear at the end
/// when [onClear] is set.
class RpeSliderCard extends StatelessWidget {
  const RpeSliderCard(
      {super.key, required this.value, required this.onChanged, this.onClear});

  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final color = rpeColor(value) ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: appCard(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Stack(alignment: Alignment.center, children: [
          Text(fmtRpe(value),
              key: const Key('rpeValue'),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: color)
                  .tabular),
          if (onClear != null)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('rpeClear'),
                style: appSmallButtonStyle(context, secondary: true),
                onPressed: onClear,
                child: const Text('Clear'),
              ),
            ),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbColor: Colors.white,
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: const Color(0x26FFFFFF),
            activeTickMarkColor: const Color(0x59FFFFFF),
            inactiveTickMarkColor: const Color(0x59FFFFFF),
            trackHeight: 4,
          ),
          child: Slider(
            key: const Key('rpeSlider'),
            value: value,
            min: 5,
            max: 10,
            divisions: 10,
            label: fmtRpe(value),
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ),
      ]),
    );
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
    // Stance's `FeedbackEditSheet`: #101010 fill.
    _sheet<SetEdit>(
      color: const Color(0xFF101010),
      context,
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
      // Stance: "Edit Set" (headlineMedium) and a small Done button, then
      // Reps | Details tabs. Cancel is our own (dismissing also cancels).
      Row(children: [
        Expanded(child: Text('Edit Set', style: theme.textTheme.headlineMedium)),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: AppColors.subtitleGray),
            child: const Text('Cancel')),
        const SizedBox(width: 8),
        FilledButton(
            key: const Key('editDone'),
            style: appSmallButtonStyle(context),
            onPressed: _done,
            child: const Text('Done')),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 20),
        child: AppSegmentedTabs<bool>(
          values: const [false, true],
          selected: _details,
          label: (d) => d ? 'Details' : 'Reps',
          keys: const {false: Key('repsTab')},
          onSelect: (d) => setState(() => _details = d),
        ),
      ),
      if (_details) ..._detailsTab(theme) else ..._repsTab(theme),
    ]);
  }

  List<Widget> _detailsTab(ThemeData theme) => [
        Text('Weight', style: _heading(context)),
        const SizedBox(height: 8),
        TextField(
          key: const Key('editWeight'),
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            suffixText: _set.unit.name,
            filled: true,
            fillColor: AppColors.cardFill,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.cardStroke)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.cardStroke)),
          ),
        ),
        const SizedBox(height: 20),
        Text('Set Type', style: _heading(context)),
        if (_setType == null) Text('Not set', style: _subtitle(context)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in SetType.values)
            ChoiceChip(
              label: Text(t.displayName),
              selected: _setType == t,
              showCheckmark: false,
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.cardFill,
              side: const BorderSide(color: AppColors.cardStroke),
              shape: const StadiumBorder(),
              onSelected: (on) => setState(() => _setType = on ? t : null),
            ),
        ]),
        const SizedBox(height: 8),
        // Stance: three full-width 48 dp buttons, 16 dp apart.
        for (final (key, label, style, onPressed) in [
          (
            const Key('copySetId'),
            _idCopied ? 'ID Copied' : 'Copy Set ID',
            appButtonStyle(context, style: AppButtonStyle.secondary, height: 48, radius: 8),
            () async {
              await Clipboard.setData(ClipboardData(text: _set.id));
              if (mounted) setState(() => _idCopied = true);
            },
          ),
          (
            const Key('reportIssue'),
            'Report Issue',
            appButtonStyle(context, height: 48, radius: 8),
            () async {
              final updated = await widget.onReportIssue(_set);
              if (mounted) setState(() => _set = updated);
            },
          ),
          (
            const Key('deleteSet'),
            'Delete Set',
            appButtonStyle(context, height: 48, style: AppButtonStyle.warning, radius: 8),
            _delete,
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: FilledButton(
                key: key, style: style, onPressed: onPressed, child: Text(label)),
          ),
      ];

  List<Widget> _repsTab(ThemeData theme) {
    final left = _timeLeft;
    final current = _set.reps.length;
    final desired = int.tryParse(_reps.text.trim());
    return [
      // Stance's `StanceEditTimerPill`.
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          key: const Key('editTimer'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0x33782EFD),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.timer_outlined, size: 14, color: AppColors.purple1),
            const SizedBox(width: 4),
            Text(
                left == Duration.zero
                    ? 'Edit Expired'
                    : '${formatTimeLeft(left)} left to edit',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.purple1)),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        child: Text('You have 7 days to edit your reps after a set.',
            style: _subtitle(context)),
      ),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: appCard(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Total reps', style: theme.textTheme.bodyLarge)),
            SizedBox(
              width: 96,
              height: 64,
              child: TextField(
                key: const Key('totalReps'),
                controller: _reps,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: theme.textTheme.headlineMedium,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text("If the rep count isn't correct then edit and tap recalculate.",
                style: _subtitle(context)),
          ),
          if (_busy) const LinearProgressIndicator(),
          FilledButton(
            key: const Key('recalculate'),
            style: appButtonStyle(context, radius: 8, height: 40),
            onPressed: _busy || desired == null || desired == current ? null : _recalculate,
            child: const Text('Recalculate'),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('checkReps'),
        style: appButtonStyle(context, style: AppButtonStyle.secondary, height: 48, radius: 8),
        onPressed: _busy ? null : _checkReps,
        child: const Text('Check Reps'),
      ),
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
    _sheet<NoteChange>(context, (_) => _ReportIssue(note: note));

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
    final bold = theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600);
    ButtonStyle choice(bool selected) => selected
        ? appButtonStyle(context, radius: 8, height: 40)
        : appButtonStyle(context, style: AppButtonStyle.secondary, radius: 8, height: 40);
    final big = appButtonStyle(context, radius: 8, height: 48);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Stance's `ReportIssueSheet`: a small Done button, the 40 sp bold
      // title, then sections 20 dp apart.
      Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 88,
          child: FilledButton(
              style: appButtonStyle(context, style: AppButtonStyle.secondary, radius: 8, height: 40),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done')),
        ),
      ),
      Text('Report Issue',
          style: theme.textTheme.displaySmall
              ?.copyWith(fontSize: 40, height: 48 / 40, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      Text('Feedback', style: bold),
      Text('Does the data look correct?',
          style: bold?.copyWith(color: AppColors.subtitleGray)),
      const SizedBox(height: 12),
      Row(children: [
        SizedBox(
          width: 64,
          child: FilledButton(
            key: const Key('dataLooksCorrect'),
            style: choice(_looksCorrect),
            onPressed: () => setState(() => _looksCorrect = true),
            child: const Text('Yes'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            key: const Key('dataLooksWrong'),
            style: choice(!_looksCorrect),
            onPressed: () => setState(() => _looksCorrect = false),
            child: const Text("No, something doesn't look right",
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ]),
      const SizedBox(height: 20),
      Text('Notes', style: bold),
      Text("Let us know what you think isn't looking right.",
          style: bold?.copyWith(color: const Color(0xFF949392))),
      const SizedBox(height: 12),
      TextField(
        key: const Key('issueNote'),
        controller: _text,
        enabled: !_looksCorrect,
        minLines: 6,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        style: theme.textTheme.bodyLarge,
        cursorColor: AppColors.primary,
        decoration: InputDecoration(
          filled: true,
          // Stance's NoteFieldFill (#27252D), dimmed while disabled.
          fillColor: Color(_looksCorrect ? 0x8027252D : 0xFF27252D),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 20),
      if (hasNote && _looksCorrect)
        FilledButton(
          key: const Key('deleteNote'),
          style: big,
          onPressed: () => Navigator.of(context).pop(const NoteChange(null)),
          child: const Text('Delete note'),
        )
      else if (hasNote)
        FilledButton(
            key: const Key('updateNote'),
            style: big,
            onPressed: _submit,
            child: const Text('Update Note'))
      else
        FilledButton(
          key: const Key('addNote'),
          style: big,
          onPressed: _looksCorrect ? null : _submit,
          child: const Text('Add Note'),
        ),
    ]);
  }
}
