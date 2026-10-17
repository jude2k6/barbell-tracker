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
import 'stance_theme.dart';
import 'stance_widgets.dart';
import 'video_review_page.dart';
import 'workout_flow.dart';

/// Stance's session feedback screen (`SessionFeedbackRoute`, notes §16),
/// for live and past sessions alike. The body compares the session with
/// an earlier one (chart, table or reps); a bottom sheet is about the
/// selected set (default: the newest): the set selector with Edit, "New
/// set" while [active], then readiness, video, RPE and rep cards that
/// open detail sheets.
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

  /// Stance's sheet peek: 196 + 18 dp, +40 when readiness has a verdict,
  /// +50 when active, +70 with the reprocess banner.
  double _peek(SetRecord set) {
    final readiness = set.reps.isEmpty
        ? null
        : buildReadiness(_withCurrent, current: _session, set: set);
    final verdict = readiness != null && _readinessVerdict(readiness, set) != null;
    return 214.0 +
        (verdict ? 40 : 0) +
        (widget.active ? 50 : 0) +
        (needsReprocessing(set) ? 70 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    // Stance's `WorkoutTopBar`: back, then the screen's actions (the guide
    // button; here also the session menu) and the device status button.
    final topBar = SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(children: [
          CircleIconButton(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Spacer(),
          _GuideHeaderButton(
            key: const Key('walkthroughButton'),
            onPressed: () => showGuide(context, feedbackWalkthroughSteps),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<VoidCallback>(
            tooltip: 'More',
            onSelected: (f) => f(),
            itemBuilder: (_) => [
              PopupMenuItem(value: _openRpeProfile, child: const Text('Edit RPE Profile')),
              PopupMenuItem(value: _deleteSession, child: const Text('Delete session')),
            ],
            child: const CircleIconButton(icon: Icons.more_vert),
          ),
          const SizedBox(width: 8),
          SensorStatusChip(sensor: _app.sensor, onPressed: () => openDevice(context)),
        ]),
      ),
    );
    return Scaffold(
      body: Stack(children: [
        SafeArea(
          bottom: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            topBar,
            Expanded(
              child: s.sets.isEmpty
                  ? const Center(child: Text('No sets in this session.'))
                  : LayoutBuilder(builder: (context, box) {
                      final peek =
                          math.min(_peek(s.sets[_selectedIndex]), box.maxHeight * 0.6);
                      final fraction = peek / box.maxHeight;
                      return Stack(children: [
                        ListView(
                          padding: EdgeInsets.fromLTRB(18, 0, 18, peek + 16),
                          children: [
                            _Header(
                                session: s,
                                onDayType: _setDayType,
                                onEditTags: _editTags),
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
            ),
          ]),
        ),
        // Stance's tag guide covers the whole screen, top bar included.
        if (_showTagPrompt && s.sets.isNotEmpty)
          Positioned.fill(
            child: _TagPrompt(onAnswer: _setDayType, onDismiss: _dismissTagPrompt),
          ),
      ]),
    );
  }
}

/// Stance's `GuideHeaderButton`: a 32 dp pill with a 2 dp Pink→Primary
/// (70 %) border, the AI mark and "Guide" in 14 sp semibold.
class _GuideHeaderButton extends StatelessWidget {
  const _GuideHeaderButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Guide',
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            height: 32,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                  colors: [Color(0xB3F415C3), Color(0xB3792EFF)]),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: StanceColors.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome, size: 20, color: StanceColors.secondaryPrime),
                SizedBox(width: 4),
                Text('Guide',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
              ]),
            ),
          ),
        ),
      );
}

/// The exercise title (headlineSmall) and Stance's `SessionDayTagDropdown`
/// (a gray tag glyph and a menu picker), plus our session tag editor.
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s.exerciseTitle, style: theme.textTheme.headlineSmall),
      const SizedBox(height: 8),
      Row(children: [
        const Icon(Icons.local_offer, size: 15, color: StanceExtraColors.gray),
        const SizedBox(width: 8),
        StanceMenuPicker<SessionDayType?>(
          key: const Key('dayTypeDropdown'),
          value: SessionDayType.fromTags(s.tags),
          values: const [null, ...SessionDayType.values],
          label: (d) => d?.displayName ?? 'None',
          onChanged: onDayType,
        ),
        const Spacer(),
        // Stance's unused `session_tag_editor_open` / `add_session_tags`
        // strings; see showSessionTagEditor.
        ExtraSmallPillButton(
          s.tags.isEmpty ? 'Add session tags' : 'Edit session tags',
          key: const Key('editSessionTags'),
          onPressed: onEditTags,
        ),
      ]),
      SessionTagsRow(tags: s.tags),
    ]);
  }
}

/// Stance's `SessionTagGuideOverlay` (a `GuideTipScaffold`): over a 60 %
/// black scrim, a card asking for the session type, which readiness and
/// session comparison match on. Picking one answers at once.
class _TagPrompt extends StatelessWidget {
  const _TagPrompt({required this.onAnswer, required this.onDismiss});

  final ValueChanged<SessionDayType> onAnswer;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onDismiss,
      child: ColoredBox(
        color: const Color(0x99000000),
        child: Align(
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () {}, // taps on the card don't dismiss it
            child: Container(
              key: const Key('tagPrompt'),
              margin: EdgeInsets.fromLTRB(
                  24, MediaQuery.paddingOf(context).top + 10, 24, 0),
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xB3B557FF), Color(0xB3792EFF)],
                ),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(15, 9, 15, 15),
                decoration: BoxDecoration(
                  color: const Color(0xFF101010),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text('Readiness',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        ExtraSmallButton('Dismiss',
                            key: const Key('dismissTagPrompt'), onPressed: onDismiss),
                      ]),
                      const SizedBox(height: 6),
                      Text('What type of session are you doing today?',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: StanceColors.subtitleGray)),
                      const SizedBox(height: 10),
                      for (final d in SessionDayType.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: StanceColors.cardFill,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: StanceExtraColors.cardStroke),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: ValueKey('dayType-${d.name}'),
                              onTap: () => onAnswer(d),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                child: Row(children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(d.displayName, style: theme.textTheme.bodyLarge),
                                ]),
                              ),
                            ),
                          ),
                        ),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stance's `FeedbackComparisonControls` and `SessionComparisonSection`:
/// "Compare:" with the date and Fastest/Last pickers, Chart / Table / Reps
/// tabs, then this session against an earlier one as a weight–velocity
/// chart, side-by-side tables, or per-set rep speeds. Tapping a set selects
/// it.
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
    final gray = theme.textTheme.bodyMedium
        ?.copyWith(color: StanceExtraColors.gray, fontWeight: FontWeight.w500);
    final speedPicker = StanceMenuPicker<SpeedChoice>(
      value: choice,
      values: SpeedChoice.values,
      label: (c) => c == SpeedChoice.fastest ? 'Fastest' : 'Last',
      onChanged: onChoice,
    );

    Widget block(String label, Color color, Widget table) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: color, fontWeight: FontWeight.w500)),
            ),
            table,
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Controls: 36 dp tall, 16 dp above and 4 dp below.
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: SizedBox(
            height: 36,
            child: Row(children: [
              if (view == ComparisonView.reps)
                Text('No comparisons for rep speed', style: gray)
              else if (candidates.isEmpty) ...[
                Expanded(
                  child: Text('No previous sessions to compare',
                      key: const Key('noComparison'), style: gray),
                ),
                speedPicker,
              ] else ...[
                const Icon(Icons.compare_arrows, size: 15, color: StanceExtraColors.gray),
                const SizedBox(width: 8),
                Text('Compare:',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: StanceExtraColors.gray)),
                const SizedBox(width: 8),
                Flexible(
                  child: StanceMenuPicker<String?>(
                    key: const Key('comparisonPicker'),
                    value: comparison?.id,
                    values: [null, for (final o in candidates) o.id],
                    label: (id) => id == null
                        ? 'Current session only'
                        : fmtDate(candidates.firstWhere((o) => o.id == id).startedAt),
                    onChanged: onComparison,
                  ),
                ),
                const SizedBox(width: 8),
                speedPicker,
              ],
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 20),
          child: StanceSegmentedTabs<ComparisonView>(
            values: ComparisonView.values,
            selected: view,
            label: (v) => v.label,
            onSelect: onView,
          ),
        ),
        switch (view) {
          ComparisonView.chart => data.points.isEmpty
              ? SizedBox(
                  height: 280,
                  child: Center(
                    child: Text('No data available for chart',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: StanceColors.subtitleGray)),
                  ),
                )
              : LoadVelocityChart(
                  data: data,
                  weightLabel: 'Weight (${unit.name})',
                  selectedSetIndex: selectedIndex,
                  onSelect: onSelect,
                  height: 280,
                ),
          ComparisonView.table => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ComparisonTableHeaders(unit: unit),
                SizedBox(
                  height: 250,
                  child: ListView(padding: EdgeInsets.zero, children: [
                    block(
                      'This Session · ${fmtDate(s.startedAt)}',
                      StanceColors.primary,
                      ComparisonTable(
                        rows: comparisonTable(s, choice),
                        unit: unit,
                        selectedSetIndex: selectedIndex,
                        onSelect: onSelect,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (comparison == null) ...[
                      Text('Comparison Session',
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: StanceColors.secondaryPrime,
                              fontWeight: FontWeight.w600)),
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 20),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: StanceColors.cardFill,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Text('No previous sessions available',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: StanceExtraColors.gray)),
                      ),
                    ] else
                      block(
                        'Comparison Session · ${fmtDate(comparison.startedAt)}',
                        StanceColors.secondaryPrime,
                        ComparisonTable(rows: comparisonTable(comparison, choice), unit: unit),
                      ),
                  ]),
                ),
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

/// Stance's readiness verdict for the mini card, if any.
ReadinessComparison? _readinessVerdict(ReadinessResult r, SetRecord set) {
  final current = readinessSpeed(set);
  if (!r.hasHistory || current == null) return null;
  return compareReadiness(
    current: current,
    lastSession: r.lastSessionSpeed,
    average: r.historicAverage,
    setType: set.setType,
    weightLabel: fmtWeight(set.weight, set.unit),
  );
}

/// The persistent bottom sheet about the selected set: Stance's
/// `BottomSheetScaffold` sheet (#2C2C2E, 30 dp top corners, a 36×4 dp
/// handle) with the set selector, reprocess banner, "New set" and the
/// readiness, video, RPE and rep cards, 16 dp from the sides.
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
      color: const Color(0xFF2C2C2E),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0x66FFFFFF),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _SetSelector(
              session: s,
              selectedIndex: selectedIndex,
              onSelect: onSelect,
              onEdit: () => onEdit(set),
            ),
          ),
          const SizedBox(height: 16),
          if (needsReprocessing(set)) ...[
            ReprocessBanner(
              state: reprocess,
              onReprocess: onReprocess,
              detail: _errorDetail(set),
            ),
            const SizedBox(height: 12),
          ],
          if (active) ...[
            FilledButton(
              key: const Key('newSet'),
              style: stanceButtonStyle(context),
              onPressed: onNewSet,
              child: const Text('New set'),
            ),
            const SizedBox(height: 16),
          ],
          if (readiness != null) ...[
            _ReadinessMiniCard(
              key: const Key('readinessMini'),
              result: readiness,
              set: set,
              onTap: () => showReadinessSheet(context, readiness, set),
            ),
            const SizedBox(height: 15),
          ],
          if (set.hasVideo) ...[
            _VideoButton(
              key: const Key('watchVideo'),
              onTap: () => onWatch(selectedIndex + 1, set),
            ),
            const SizedBox(height: 15),
          ],
          _RpeCard(key: const Key('rpeCard'), rpe: set.rpe, onTap: () => onRpe(set)),
          const SizedBox(height: 15),
          _CardTap(
            key: const Key('repSpeedMini'),
            onTap: () => showRepSpeedSheet(context,
                session: s, setIndex: selectedIndex, all: all),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text('Reps', style: theme.textTheme.bodyLarge),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: RepVelocityChart(
                  velocities: [for (final r in set.reps) r.meanVelocity],
                  height: 182,
                ),
              ),
            ]),
          ),
          if (set.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(set.note!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: StanceColors.subtitleGray)),
            ),
          const SizedBox(height: 12),
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
}

/// Stance's `FeedbackSetSelector`: ‹ and › circle buttons around the set's
/// type (gray), weight (17 sp bold; red with a note) over an "Edit" pill,
/// and rep count (gray).
class _SetSelector extends StatelessWidget {
  const _SetSelector({
    required this.session,
    required this.selectedIndex,
    required this.onSelect,
    required this.onEdit,
  });

  final Session session;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final set = session.sets[selectedIndex];
    final i = selectedIndex;
    final hasPrevious = i > 0, hasNext = i < session.sets.length - 1;
    // Stance's StanceSubheadlineMedium (15/20) and StanceHeadlineBold (17/22).
    const sub = TextStyle(
        fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w500, color: StanceExtraColors.gray);
    final weight = set.weight > 0 ? fmtWeight(set.weight, set.unit) : 'Set ${i + 1}';
    // Stance's CircularIconButton, the chevron gray at either end.
    Widget arrow(IconData icon, bool enabled, int to, String key, String tip) =>
        Tooltip(
          message: tip,
          child: InkWell(
            key: Key(key),
            customBorder: const CircleBorder(),
            onTap: enabled ? () => onSelect(to) : null,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0x0DFFFFFF)),
              child: Icon(icon,
                  color: enabled ? Colors.white : StanceExtraColors.gray),
            ),
          ),
        );
    // The summary is our own: Stance's selector has no set number. It is
    // the selector's semantics label (and what tests look for).
    final summary = [
      'Set ${i + 1}',
      if (set.weight > 0) fmtWeight(set.weight, set.unit),
      if (set.setType != null) set.setType!.displayName,
      '${set.reps.length} reps',
    ].join(' · ');
    return Semantics(
      key: const Key('selectedSetSummary'),
      container: true,
      explicitChildNodes: true,
      label: summary,
      child: Row(key: const Key('setSelector'), children: [
        arrow(Icons.keyboard_arrow_left, hasPrevious, i - 1, 'previousSet', 'Previous set'),
        const SizedBox(width: 16),
        Expanded(
          child: Text(set.setType?.shortName ?? '', style: sub, maxLines: 1),
        ),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              weight,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                height: 22 / 17,
                fontWeight: FontWeight.w700,
                color: set.note != null ? Colors.red : Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            ExtraSmallPillButton('Edit', key: const Key('editSet'), onPressed: onEdit),
          ]),
        ),
        Expanded(
          child: Text(set.reps.isEmpty ? '' : '${set.reps.length} Reps',
              style: sub, textAlign: TextAlign.end, maxLines: 1),
        ),
        const SizedBox(width: 16),
        arrow(Icons.keyboard_arrow_right, hasNext, i + 1, 'nextSet', 'Next set'),
      ]),
    );
  }
}

/// A [stanceCard] that is one tap target.
class _CardTap extends StatelessWidget {
  const _CardTap({super.key, required this.onTap, required this.child, this.radius = 20});

  final VoidCallback onTap;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => Material(
        color: StanceColors.cardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: StanceExtraColors.cardStroke),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: child),
      );
}

/// Stance's `FeedbackReadinessMiniCard`: "Readiness", the verdict row when
/// there is one, then This Session (Primary), Last Session (PrimaryLight)
/// and Average (PrimaryVariant) speeds over 2 dp colour bars.
class _ReadinessMiniCard extends StatelessWidget {
  const _ReadinessMiniCard(
      {super.key, required this.result, required this.set, required this.onTap});

  final ReadinessResult result;
  final SetRecord set;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verdict = _readinessVerdict(result, set);
    Widget column(String label, double? speed, Color color, bool current) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Flexible(
                child: Text(
                  speed == null || speed <= 0 ? '--' : speed.toStringAsFixed(2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (current
                          ? theme.textTheme.headlineMedium
                          : theme.textTheme.titleLarge)
                      ?.copyWith(fontWeight: FontWeight.w700)
                      .tabular,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 3),
                child: Text('m/s',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500)),
              ),
            ]),
            const SizedBox(height: 4),
            Container(
              height: 2,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: StanceColors.subtitleGray, fontWeight: FontWeight.w500)),
          ],
        );
    return _CardTap(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Readiness',
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
          ),
          if (verdict != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ReadinessVerdictRow(verdict: verdict, onSeeMore: onTap),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                flex: 130,
                child: column('This Session', readinessSpeed(set), StanceColors.primary, true)),
            const SizedBox(width: 6),
            Expanded(
                flex: 90,
                child: column('Last Session', result.lastSessionSpeed,
                    StanceColors.primaryLight, false)),
            const SizedBox(width: 6),
            Expanded(
                flex: 90,
                child: column('Average', result.historicAverage,
                    StanceColors.primaryVariant, false)),
          ]),
        ]),
      ),
    );
  }
}

/// Stance's `MiniComparisonRow`: in a #201B28 + Primary 8 % banner with a
/// Pink→Primary border, the verdict ("Faster" with a bolt, "Slower" with
/// an hourglass), "Let's go!" when faster, and "See More".
class _ReadinessVerdictRow extends StatelessWidget {
  const _ReadinessVerdictRow({required this.verdict, required this.onSeeMore});

  final ReadinessComparison verdict;
  final VoidCallback onSeeMore;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
              colors: [StanceExtraColors.pink, StanceColors.primary]),
        ),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            // Primary 8 % over FourgroundSolid.
            color: Color.alphaBlend(
                const Color(0x14792EFF), StanceExtraColors.fourgroundSolid),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(children: [
            ExtraSmallButton(verdict.title,
                icon: verdict.isFaster ? Icons.bolt : Icons.hourglass_bottom,
                leadingIcon: true,
                onPressed: onSeeMore),
            if (verdict.isFaster) ...[
              const SizedBox(width: 8),
              Text("Let's go!",
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
            const Spacer(),
            ExtraSmallButton('See More', onPressed: onSeeMore),
          ]),
        ),
      );
}

/// Stance's `FeedbackVideoButton`: a 100 dp card (Stance shows the video's
/// first frame behind it) with "Recording" and a white 12 % "Preview" pill.
class _VideoButton extends StatelessWidget {
  const _VideoButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 100,
      child: _CardTap(
        radius: 16,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Text('Recording', style: theme.textTheme.bodyLarge),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.play_arrow, size: 16, color: Colors.white),
                const SizedBox(width: 4),
                Text('Preview',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Stance's `FeedbackRpeCard`: "RPE", then the RPE badge or "What RPE was
/// the set?", and an edit circle button.
class _RpeCard extends StatelessWidget {
  const _RpeCard({super.key, required this.rpe, required this.onTap});

  final double? rpe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = rpe;
    return _CardTap(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Text('RPE', style: theme.textTheme.bodyLarge),
          const SizedBox(width: 12),
          if (r == null)
            Flexible(
              child: Text('What RPE was the set?',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: StanceColors.subtitleGray)),
            )
          else
            _RpeBadge(r),
          const Spacer(),
          CircleIconButton(icon: Icons.edit_outlined, onPressed: onTap),
        ]),
      ),
    );
  }
}

/// Stance's `StanceRpeBadge`: a 44 dp circle in the RPE colour at 25 %,
/// the value in that colour (22 sp, 16 sp when longer than two chars).
class _RpeBadge extends StatelessWidget {
  const _RpeBadge(this.rpe);

  final double rpe;

  @override
  Widget build(BuildContext context) {
    final color = rpeColor(rpe) ?? StanceColors.primary;
    final text = fmtRpe(rpe);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.25)),
      child: Text(text,
          key: const Key('rpeCardValue'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: color, fontSize: text.length > 2 ? 16 : 22).tabular),
    );
  }
}
