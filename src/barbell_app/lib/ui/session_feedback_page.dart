import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../video/set_video_recorder.dart';
import '../workout/guide_tips.dart';
import '../workout/load_velocity.dart';
import '../workout/preferences.dart';
import '../workout/readiness.dart';
import '../workout/reprocess.dart';
import '../workout/rep_editing.dart';
import '../workout/rpe_profile.dart';
import '../workout/session.dart';
import '../workout/session_comparison.dart';
import '../workout/session_tags.dart';
import '../workout/set_metrics.dart';
import 'app_scope.dart';
import 'charts/load_velocity_chart.dart';
import 'charts/rep_velocity_chart.dart';
import 'charts/rpe_profile_chart.dart';
import 'comparison_views.dart';
import 'feedback_sheets.dart';
import 'format.dart';
import 'guides.dart';
import 'rep_check_page.dart';
import 'reprocess_banner.dart';
import 'rpe_profile_page.dart';
import 'sensor_status_chip.dart';
import 'session_tag_editor.dart';
import 'video_review_page.dart';
import 'workout_flow.dart';

/// Stance's session feedback screen (notes §16), for live and past
/// sessions alike. The body compares the session with an earlier one
/// (chart, table or reps); a bottom sheet is about the selected set
/// (default: the newest): set chips with Edit, "New set" while [active],
/// then readiness, video, RPE and rep-speed cards that open detail sheets.
///
/// Follows the session in the store, so a set added or edited elsewhere
/// shows up; a newly added set becomes the selected one.
class SessionFeedbackPage extends StatefulWidget {
  const SessionFeedbackPage({super.key, required this.session, this.active = false});

  final Session session;

  /// Live or still continuable: shows "New set".
  final bool active;

  @override
  State<SessionFeedbackPage> createState() => _SessionFeedbackPageState();
}

class _SessionFeedbackPageState extends State<SessionFeedbackPage> {
  late final AppScope _app = AppScope.of(context);
  late Session _session = widget.session;

  /// Every saved session, for comparison, readiness, RPE profile and
  /// same-weight history.
  List<Session> _all = const [];
  bool _listening = false;

  /// Selected set's id; null means the newest set.
  String? _selectedId;

  SpeedChoice _choice = SpeedChoice.fastest;
  ComparisonView _view = ComparisonView.chart;

  /// Chosen comparison session; null means the newest candidate.
  String? _comparisonId;
  bool _currentOnly = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listening) return;
    _listening = true;
    _app.sessions.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _guideTimer?.cancel();
    _app.sessions.removeListener(_reload);
    super.dispose();
  }

  /// The session-type question was dismissed on this visit.
  bool _tagPromptDismissed = false;

  /// Stance's tag guide: asked whenever the session has no session type.
  bool get _showTagPrompt =>
      !_tagPromptDismissed && !hasSessionTypeTag(_session.tags);

  /// Stance's `updateDayType`: replaces the `Day:` tag (none for null).
  /// Comparison sessions depend on it, so the picked one is reset.
  Future<void> _setDayType(SessionDayType? type) async {
    final updated = _session.copyWith(tags: withDayType(_session.tags, type));
    setState(() {
      _session = updated;
      _comparisonId = null;
      _currentOnly = false;
    });
    await _app.sessions.save(updated);
    _scheduleGuide();
  }

  /// Stance's `applyTagsFromEditor`: saves the edited tags and reloads
  /// the comparison, like a day type change.
  Future<void> _editTags() async {
    final tags = await showSessionTagEditor(context, _session.tags);
    if (!mounted || listEquals(tags, _session.tags)) return;
    final updated = _session.copyWith(tags: tags);
    setState(() {
      _session = updated;
      _comparisonId = null;
      _currentOnly = false;
    });
    await _app.sessions.save(updated);
    _scheduleGuide();
  }

  void _dismissTagPrompt() {
    setState(() => _tagPromptDismissed = true);
    _scheduleGuide();
  }

  /// First-run walkthrough or one guide tip, at most once per visit.
  Timer? _guideTimer;
  bool _guideScheduled = false;

  /// Stance's guides (notes §17): the walkthrough 2 s after the first ever
  /// visit, else the first unseen tip that applies to the selected set.
  void _scheduleGuide() {
    final prefs = _app.preferences;
    if (prefs == null || _guideScheduled || _session.sets.isEmpty) return;
    // Stance holds guide tips back while the session-type question shows.
    if (_showTagPrompt) return;
    _guideScheduled = true;
    if (!prefs.hasSeen(Guide.feedbackWalkthrough)) {
      _guideTimer = Timer(const Duration(seconds: 2), () {
        if (!_canShowGuide) return;
        prefs.markSeen(Guide.feedbackWalkthrough);
        showGuide(context, feedbackWalkthroughSteps);
      });
      return;
    }
    final set = _session.sets[_selectedIndex];
    final tip = firstEligibleTip(
      hasSeen: prefs.hasSeen,
      set: set,
      readiness: set.reps.isEmpty
          ? ReadinessResult.empty
          : buildReadiness(_withCurrent, current: _session, set: set),
      weightLabel: fmtWeight(set.weight, set.unit),
      dayTypeName: SessionDayType.fromTags(_session.tags)?.displayName,
    );
    if (tip == null) return;
    _guideTimer = Timer(tip.delay, () {
      if (!_canShowGuide) return;
      prefs.markSeen(tip.guide);
      showGuideTip(context, tip);
    });
  }

  /// Only over this page itself, not over a sheet or another page.
  bool get _canShowGuide => mounted && (ModalRoute.of(context)?.isCurrent ?? false);

  /// Counts reloads, so a slower, older one can't overwrite a newer one.
  int _reloads = 0;

  Future<void> _reload() async {
    final generation = ++_reloads;
    final store = _app.sessions;
    final fresh = await store.load(_session.id);
    final all = await store.list();
    if (!mounted || generation != _reloads) return;
    setState(() {
      if (fresh != null) {
        // A new set (back from recording) becomes the selected one.
        if (fresh.sets.length > _session.sets.length) _selectedId = null;
        _session = fresh;
      }
      _all = all;
    });
    _scheduleGuide();
  }

  /// Stance's `selectSet`: also resets the reprocess banner.
  void _select(String id) => setState(() {
        _selectedId = id;
        _reprocess = ReprocessState.idle;
      });

  /// The reprocess banner's state for the selected set.
  ReprocessState _reprocess = ReprocessState.idle;

  /// Stance's `reprocessSelectedSet`, from the set's raw CSV.
  Future<void> _reprocessSelected() async {
    if (_reprocess == ReprocessState.inProgress) return;
    final set = _session.sets[_selectedIndex];
    final exercise = _session.exercise;
    setState(() => _reprocess = ReprocessState.inProgress);
    final result = exercise == null
        ? const ReprocessUnavailable()
        : await reprocessSet(set,
            exercise: exercise, recordings: _app.recordings, analyze: _app.analyzer);
    if (!mounted) return;
    if (result case ReprocessSuccess(set: final updated)) {
      // Keep edits made while it ran (only analysis fields come from it).
      final latest = _latest(set.id);
      if (latest != null) {
        await _saveSet(latest.withAnalysis(
          reps: updated.reps,
          pipeline: updated.pipeline!,
          warnings: updated.warnings,
          measuredHz: updated.measuredHz!,
          velocityTrace: updated.velocityTrace,
          traceHz: updated.traceHz,
          videoOffsetSec: updated.videoOffsetSec,
        ));
      }
    }
    if (mounted) setState(() => _reprocess = stateAfter(result));
  }

  int get _selectedIndex {
    final i = _session.sets.indexWhere((s) => s.id == _selectedId);
    return i >= 0 ? i : _session.sets.length - 1;
  }

  List<Session> get _others => [
        for (final o in _all)
          if (o.id != _session.id) o,
      ];

  /// The session as saved plus every other one.
  List<Session> get _withCurrent => [_session, ..._others];

  Future<void> _saveSet(SetRecord set) async {
    final updated = _session.replaceSet(set);
    setState(() => _session = updated);
    await _app.sessions.save(updated);
  }

  /// The saved copy of the set with [id] (it may have changed since).
  SetRecord? _latest(String id) =>
      _session.sets.where((s) => s.id == id).firstOrNull;

  Future<SetRecord?> _checkReps(SetRecord set) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RepCheckPage(
        set: set,
        preferences: _app.preferences,
        onCommit: (markers) async {
          final edited = applyRepMarkers(_latest(set.id) ?? set, markers);
          if (edited != null) await _saveSet(edited);
          return edited;
        },
      ),
    ));
    return _latest(set.id);
  }

  Future<SetRecord> _reportIssue(SetRecord set) async {
    final change = await showReportIssueSheet(context, set.note);
    if (change == null) return set;
    final updated = change.note == null
        ? set.copyWith(clearNote: true)
        : set.copyWith(note: change.note);
    await _saveSet(updated);
    return updated;
  }

  Future<void> _editSet(SetRecord set) async {
    final edit = await showEditSetSheet(
      context,
      set: set,
      deadlift: _session.exercise?.isDeadlift ?? false,
      onSave: (s) async {
        await _saveSet(s);
        return s;
      },
      onCheckReps: _checkReps,
      onReportIssue: _reportIssue,
    );
    if (!mounted) return;
    switch (edit) {
      case SetEdited(:final set):
        await _saveSet(set);
      case SetDeleted():
        final rest = [
          for (final s in _session.sets)
            if (s.id != set.id) s,
        ];
        if (rest.isEmpty) {
          await _app.sessions.delete(_session.id);
          if (mounted) Navigator.of(context).pop();
          return;
        }
        final updated = _session.copyWith(sets: rest);
        setState(() {
          _session = updated;
          _selectedId = null;
        });
        await _app.sessions.save(updated);
      case null:
        break;
    }
  }

  Future<void> _openRpe(SetRecord set) async {
    final speed = lastRepSpeed(set);
    final profile = speed == null
        ? null
        : buildRpeProfile(_withCurrent, exerciseId: _session.exerciseId, speed: speed);
    final choice = await showRpeSheet(
      context,
      set: set,
      profile: profile,
      onEditProfile: _openRpeProfile,
    );
    if (choice == null || !mounted) return;
    await _saveSet(choice.rpe == null
        ? set.copyWith(clearRpe: true)
        : set.copyWith(rpe: choice.rpe));
  }

  Future<void> _openRpeProfile() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RpeProfilePage(
          exerciseId: _session.exerciseId,
          exerciseTitle: _session.exerciseTitle,
        ),
      ));

  Future<void> _watch(int number, SetRecord set) async {
    final file = await SetVideoRecorder().resolve(set.videoFile!);
    if (!mounted) return;
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Video file not found.')));
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoReviewPage(
        set: set,
        video: file,
        title: 'Set $number · ${fmtWeight(set.weight, set.unit)}',
        onSaveOffset: (offset) => _saveSet(set.copyWith(videoOffsetSec: offset)),
      ),
    ));
  }

  Future<void> _deleteSession() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete session?'),
        content: const Text(
            'The session and its results are removed. Raw recordings are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _app.sessions.delete(_session.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.exerciseTitle),
        actions: [
          IconButton(
            key: const Key('walkthroughButton'),
            tooltip: 'Guide',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showGuide(context, feedbackWalkthroughSteps),
          ),
          SensorStatusChip(sensor: _app.sensor, onPressed: () => openDevice(context)),
          PopupMenuButton<VoidCallback>(
            onSelected: (f) => f(),
            itemBuilder: (_) => [
              PopupMenuItem(value: _openRpeProfile, child: const Text('Edit RPE Profile')),
              PopupMenuItem(value: _deleteSession, child: const Text('Delete session')),
            ],
          ),
        ],
      ),
      body: s.sets.isEmpty
          ? const Center(child: Text('No sets in this session.'))
          : LayoutBuilder(builder: (context, box) {
              // Stance's sheet peek: 214 dp, +50 when active.
              // +70 with the reprocess banner, as Stance.
              final banner = needsReprocessing(s.sets[_selectedIndex]);
              final peek = math.min(
                  240.0 + (widget.active ? 56 : 0) + (banner ? 70 : 0),
                  box.maxHeight * 0.6);
              final fraction = peek / box.maxHeight;
              return Stack(children: [
                ListView(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, peek + 16),
                  children: [
                    _Header(
                        session: s,
                        onDayType: _setDayType,
                        onEditTags: _editTags),
                    if (_showTagPrompt)
                      _TagPrompt(onAnswer: _setDayType, onDismiss: _dismissTagPrompt),
                    _ComparisonSection(
                      session: s,
                      others: _others,
                      selectedIndex: _selectedIndex,
                      onSelect: (i) => _select(s.sets[i].id),
                      choice: _choice,
                      onChoice: (c) => setState(() => _choice = c),
                      view: _view,
                      onView: (v) => setState(() => _view = v),
                      comparisonId: _currentOnly ? null : _comparisonId,
                      currentOnly: _currentOnly,
                      onComparison: (id) => setState(() {
                        _currentOnly = id == null;
                        _comparisonId = id;
                      }),
                    ),
                  ],
                ),
                DraggableScrollableSheet(
                  key: const Key('setSheet'),
                  initialChildSize: fraction,
                  minChildSize: fraction,
                  maxChildSize: 0.92,
                  snap: true,
                  builder: (context, controller) => _SetSheet(
                    controller: controller,
                    session: s,
                    all: _withCurrent,
                    selectedIndex: _selectedIndex,
                    active: widget.active && s.exercise != null,
                    onSelect: (i) => _select(s.sets[i].id),
                    onEdit: _editSet,
                    onNewSet: () => startSet(context, s.exercise!, session: s),
                    onRpe: _openRpe,
                    onWatch: _watch,
                    reprocess: _reprocess,
                    onReprocess: _reprocessSelected,
                  ),
                ),
              ]);
            }),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.session,
      required this.onDayType,
      required this.onEditTags});

  final Session session;
  final ValueChanged<SessionDayType?> onDayType;
  final VoidCallback onEditTags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    final end = s.endedAt;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        '${fmtDate(s.startedAt)}, ${fmtTime(s.startedAt)}'
        '${end == null ? '' : '–${fmtTime(end)}'}',
        style: theme.textTheme.bodyMedium.tabular,
      ),
      Text(
        '${s.sets.length} sets · ${s.totalReps} reps · '
        'best ${fmtVelocity(s.bestMeanVelocity)} m/s',
        style: theme.textTheme.bodyMedium.tabular,
      ),
      const SizedBox(height: 4),
      // Stance's `SessionDayTagDropdown`: None or one of the four types.
      DropdownButton<SessionDayType?>(
        key: const Key('dayTypeDropdown'),
        value: SessionDayType.fromTags(s.tags),
        hint: const Text('Day: None'),
        items: [
          const DropdownMenuItem(value: null, child: Text('Day: None')),
          for (final d in SessionDayType.values)
            DropdownMenuItem(value: d, child: Text('Day: ${d.displayName}')),
        ],
        onChanged: onDayType,
      ),
      // Stance's unused `session_tag_editor_open` / `add_session_tags`
      // strings; see showSessionTagEditor.
      TextButton.icon(
        key: const Key('editSessionTags'),
        onPressed: onEditTags,
        icon: const Icon(Icons.local_offer_outlined),
        label: Text(s.tags.isEmpty ? 'Add session tags' : 'Edit session tags'),
      ),
      SessionTagsRow(tags: s.tags),
    ]);
  }
}

/// Stance's `SessionTagGuideOverlay`: asks for the session type, which
/// readiness and session comparison match on.
class _TagPrompt extends StatelessWidget {
  const _TagPrompt({required this.onAnswer, required this.onDismiss});

  final ValueChanged<SessionDayType> onAnswer;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('tagPrompt'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Readiness', style: theme.textTheme.titleSmall)),
            IconButton(
              key: const Key('dismissTagPrompt'),
              tooltip: 'Not now',
              icon: const Icon(Icons.close),
              onPressed: onDismiss,
            ),
          ]),
          const Text('What type of session are you doing today?'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final d in SessionDayType.values)
              ActionChip(
                key: ValueKey('dayType-${d.name}'),
                label: Text(d.displayName),
                onPressed: () => onAnswer(d),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// Stance's comparison controls and section: this session against an
/// earlier one as a weight–velocity chart, side-by-side tables, or per-set
/// rep speeds. Tapping a set selects it.
class _ComparisonSection extends StatelessWidget {
  const _ComparisonSection({
    required this.session,
    required this.others,
    required this.selectedIndex,
    required this.onSelect,
    required this.choice,
    required this.onChoice,
    required this.view,
    required this.onView,
    required this.comparisonId,
    required this.currentOnly,
    required this.onComparison,
  });

  final Session session;

  /// Other saved sessions (any exercise).
  final List<Session> others;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final SpeedChoice choice;
  final ValueChanged<SpeedChoice> onChoice;
  final ComparisonView view;
  final ValueChanged<ComparisonView> onView;
  final String? comparisonId;
  final bool currentOnly;
  final ValueChanged<String?> onComparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    final unit =
        s.sets.where((set) => set.weight > 0).lastOrNull?.unit ?? WeightUnit.kg;
    final candidates = comparisonCandidates(others, s);
    final comparison = currentOnly
        ? null
        : candidates.where((o) => o.id == comparisonId).firstOrNull ??
            candidates.firstOrNull;
    final data =
        buildLoadVelocity(s, unit: unit, comparison: comparison, choice: choice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        if (candidates.isEmpty)
          Text(
              hasSessionTypeTag(s.tags)
                  ? 'No previous sessions to compare'
                  : 'Pick a day type to compare with earlier sessions of that type.',
              key: const Key('noComparison'),
              style: theme.textTheme.bodySmall)
        else
          Row(children: [
            Text('Compare:', style: theme.textTheme.labelLarge),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String?>(
                key: const Key('comparisonPicker'),
                isExpanded: true,
                value: comparison?.id,
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Current session only')),
                  for (final o in candidates)
                    DropdownMenuItem(value: o.id, child: Text(fmtDate(o.startedAt))),
                ],
                onChanged: onComparison,
              ),
            ),
          ]),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, children: [
          SegmentedButton<ComparisonView>(
            segments: [
              for (final v in ComparisonView.values)
                ButtonSegment(value: v, label: Text(v.label)),
            ],
            selected: {view},
            showSelectedIcon: false,
            onSelectionChanged: (v) => onView(v.first),
          ),
          if (view != ComparisonView.reps)
            SegmentedButton<SpeedChoice>(
              segments: const [
                ButtonSegment(value: SpeedChoice.fastest, label: Text('Fastest')),
                ButtonSegment(value: SpeedChoice.last, label: Text('Last')),
              ],
              selected: {choice},
              showSelectedIcon: false,
              onSelectionChanged: (v) => onChoice(v.first),
            ),
        ]),
        const SizedBox(height: 8),
        switch (view) {
          ComparisonView.chart => data.points.isEmpty
              ? const Text('No sets with a weight and reps to chart.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LoadVelocityChart(
                      data: data,
                      weightLabel: 'Weight (${unit.name})',
                      selectedSetIndex: selectedIndex,
                      onSelect: onSelect,
                    ),
                    if (comparison != null)
                      Text(
                        'Second colour: ${fmtDayMonth(comparison.startedAt)} session',
                        style: theme.textTheme.labelSmall,
                      ),
                  ],
                ),
          ComparisonView.table => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('This Session · ${fmtDate(s.startedAt)}',
                    style: theme.textTheme.labelLarge),
                ComparisonTable(
                  rows: comparisonTable(s, choice),
                  unit: unit,
                  selectedSetIndex: selectedIndex,
                  onSelect: onSelect,
                ),
                const SizedBox(height: 16),
                if (comparison == null)
                  Text(
                      candidates.isEmpty
                          ? 'No previous sessions available'
                          : 'Current session only',
                      style: theme.textTheme.bodySmall)
                else ...[
                  Text('Comparison Session · ${fmtDate(comparison.startedAt)}',
                      style: theme.textTheme.labelLarge),
                  ComparisonTable(rows: comparisonTable(comparison, choice), unit: unit),
                ],
              ],
            ),
          ComparisonView.reps => RepSpeedRow(
              session: s,
              selectedSetIndex: selectedIndex,
              onSelect: onSelect,
            ),
        },
      ],
    );
  }
}

/// The persistent bottom sheet about the selected set.
class _SetSheet extends StatelessWidget {
  const _SetSheet({
    required this.controller,
    required this.session,
    required this.all,
    required this.selectedIndex,
    required this.active,
    required this.onSelect,
    required this.onEdit,
    required this.onNewSet,
    required this.onRpe,
    required this.onWatch,
    required this.reprocess,
    required this.onReprocess,
  });

  final ScrollController controller;
  final Session session;

  /// Every saved session including this one.
  final List<Session> all;
  final int selectedIndex;
  final bool active;
  final ValueChanged<int> onSelect;
  final ValueChanged<SetRecord> onEdit;
  final VoidCallback onNewSet;
  final ValueChanged<SetRecord> onRpe;
  final void Function(int number, SetRecord set) onWatch;
  final ReprocessState reprocess;
  final VoidCallback onReprocess;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    final set = s.sets[selectedIndex];
    final readiness =
        set.reps.isEmpty ? null : buildReadiness(all, current: s, set: set);

    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  key: const Key('setSelector'),
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  itemCount: s.sets.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, j) {
                    // Newest first, like Stance's selector.
                    final i = s.sets.length - 1 - j;
                    final o = s.sets[i];
                    return ChoiceChip(
                      key: ValueKey('setChip-$i'),
                      label: Text(
                        'Set ${i + 1}'
                        '${o.weight > 0 ? ' · ${fmtWeight(o.weight, o.unit)}' : ''}',
                      ),
                      selected: i == selectedIndex,
                      onSelected: (_) => onSelect(i),
                    );
                  },
                ),
              ),
            ),
            IconButton(
              key: const Key('editSet'),
              tooltip: 'Edit set',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => onEdit(set),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            [
              'Set ${selectedIndex + 1}',
              if (set.weight > 0) fmtWeight(set.weight, set.unit),
              if (set.setType != null) set.setType!.displayName,
              '${set.reps.length} reps',
            ].join(' · '),
            key: const Key('selectedSetSummary'),
            style: theme.textTheme.titleSmall.tabular,
          ),
          if (needsReprocessing(set)) ...[
            const SizedBox(height: 8),
            ReprocessBanner(
              state: reprocess,
              onReprocess: onReprocess,
              detail: _errorDetail(set),
            ),
          ],
          if (active) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('newSet'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: onNewSet,
              icon: const Icon(Icons.add),
              label: const Text('New set'),
            ),
          ],
          const SizedBox(height: 12),
          if (readiness != null)
            _MiniCard(
              key: const Key('readinessMini'),
              title: 'Readiness',
              subtitle: _readinessLine(readiness, set),
              trailing: Text(fmtVelocity(readinessSpeed(set)),
                  style: theme.textTheme.titleMedium.tabular),
              onTap: () => showReadinessSheet(context, readiness, set),
            ),
          if (set.hasVideo)
            _MiniCard(
              key: const Key('watchVideo'),
              title: 'Watch video',
              subtitle: 'With the velocity overlay',
              trailing: const Icon(Icons.play_circle_outline),
              onTap: () => onWatch(selectedIndex + 1, set),
            ),
          _MiniCard(
            key: const Key('rpeCard'),
            title: 'RPE',
            subtitle: set.rpe == null ? 'Tap to add how hard the set felt' : null,
            trailing: set.rpe == null
                ? const Icon(Icons.add)
                : Text(fmtRpe(set.rpe),
                    key: const Key('rpeCardValue'),
                    style: theme.textTheme.titleLarge.tabular
                        ?.copyWith(color: rpeColor(set.rpe!))),
            onTap: () => onRpe(set),
          ),
          _MiniCard(
            key: const Key('repSpeedMini'),
            title: 'Rep speed',
            subtitle: set.reps.isEmpty
                ? 'No reps detected for this set.'
                : 'Max ${fmtVelocity(set.reps.bestMeanVelocity)} · '
                    'Avg ${fmtVelocity(set.reps.avgMeanVelocity)} m/s'
                    '${set.reps.velocityLossPct == null ? '' : ' · loss ${fmtPct(set.reps.velocityLossPct)}'}',
            trailing: set.reps.isEmpty
                ? null
                : SizedBox(
                    width: 96,
                    child: RepVelocityChart(
                      velocities: [for (final r in set.reps) r.meanVelocity],
                      showAxes: false,
                      height: 44,
                    ),
                  ),
            onTap: () => showRepSpeedSheet(context,
                session: s, setIndex: selectedIndex, all: all),
          ),
          if (set.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(set.note!, style: theme.textTheme.bodyMedium),
            ),
        ]),
      ),
    );
  }

  /// The stored analysis error and the raw file's name, under the banner.
  static String? _errorDetail(SetRecord set) {
    final error = set.analysisError;
    if (error == null) return null;
    final raw = set.rawCsvFile;
    return raw == null ? error : '$error\nRaw recording saved as ${raw.split('/').last}.';
  }

  static String _readinessLine(ReadinessResult r, SetRecord set) {
    final current = readinessSpeed(set);
    if (!r.hasHistory || current == null) return 'No historical data available';
    final c = compareReadiness(
      current: current,
      lastSession: r.lastSessionSpeed,
      average: r.historicAverage,
      setType: set.setType,
      weightLabel: fmtWeight(set.weight, set.unit),
    );
    return c?.title ??
        'Last ${fmtVelocity(r.lastSessionSpeed)} · Avg ${fmtVelocity(r.historicAverage)} m/s';
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          onTap: onTap,
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing: trailing,
        ),
      );
}
