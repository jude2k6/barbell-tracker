import 'package:flutter/material.dart';

import '../analysis/exercises.dart';
import '../workout/active_session.dart';
import '../workout/load_velocity.dart';
import '../workout/preferences.dart';
import '../workout/sensor_controller.dart';
import '../workout/session.dart';
import '../workout/set_metrics.dart';
import 'app_scope.dart';
import 'charts/rpe_profile_chart.dart' show rpeColor;
import 'format.dart';
import 'permission_prompts.dart';
import 'session_tag_editor.dart';
import 'sensor_status_chip.dart';
import 'sessions_builder.dart';
import 'stance_theme.dart';
import 'stance_widgets.dart';
import 'workout_flow.dart';

/// Stance's `SessionListRoute`: the workout top bar, "Sessions" over the
/// exercise name, a card per session (newest first) and, while no session
/// is active, a "New Session" button at the bottom. The newest session is
/// continuable for an hour after its last set (`activeSessionId`); its
/// card is highlighted and says Continue, the others View.
class SessionsPage extends StatelessWidget {
  const SessionsPage({super.key, required this.exercise, this.now});

  final Exercise exercise;

  /// Clock for the active-session rule; defaults to now (tests).
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final unit = app.preferences?.value.weightUnit ?? const Preferences().weightUnit;
    return Scaffold(
      body: SafeArea(
        child: SessionsBuilder(
          store: app.sessions,
          builder: (context, all) {
            final sessions = [
              for (final s in all ?? const <Session>[])
                if (s.exerciseId == exercise.id) s,
            ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
            final active = activeSessionId(sessions, exercise.id, now: now?.call());
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WorkoutTopBar(sensor: app.sensor),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('Sessions', style: theme.textTheme.headlineLarge),
                        if (all == null) ...[
                          const SizedBox(width: 8),
                          const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          ),
                        ],
                      ]),
                      Text(exercise.rawValue,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: const Color(0x66FFFFFF))),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                    children: [
                      if (all != null && sessions.isEmpty) const _SessionEmptyCard(),
                      for (final s in sessions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _SessionCard(
                            session: s,
                            unit: unit,
                            active: s.id == active,
                            onOpen: () => openSessionFeedback(context, s,
                                active: s.id == active),
                          ),
                        ),
                    ],
                  ),
                ),
                if (active == null)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: _StanceButton(
                      key: const Key('newSession'),
                      label: 'New Session',
                      height: 48,
                      onPressed: () => _newSession(context, exercise),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// New Session. With no sensor connected, first warns if Location Services is
/// off (Android 11 and older can't find the sensor then), with "Continue
/// anyway" (Stance's `readinessPromptForNewSession`).
Future<void> _newSession(BuildContext context, Exercise exercise) async {
  final app = AppScope.of(context);
  final permissions = app.permissions;
  if (permissions != null && !app.sensor.isStreaming) {
    if (!await ensureLocationServices(context, permissions, continueAnyway: true)) return;
    if (!context.mounted) return;
  }
  await startSet(context, exercise);
}

/// Stance's `WorkoutTopBar`: a 44 dp row, 18 dp in from the sides, with
/// the back button and the device status.
class _WorkoutTopBar extends StatelessWidget {
  const _WorkoutTopBar({required this.sensor});

  final SensorController sensor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(children: [
        CircleIconButton(
          key: const Key('workoutBack'),
          icon: Icons.arrow_back,
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        SensorStatusChip(sensor: sensor, onPressed: () => openDevice(context)),
      ]),
    );
  }
}

/// Stance's `StanceButton` (Primary, or Idle while disabled): white
/// bodyLarge semibold on the primary colour, 16 dp corners.
class _StanceButton extends StatelessWidget {
  const _StanceButton(
      {super.key, required this.label, required this.onPressed, this.height = 42});

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: Size.fromHeight(height),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: StanceColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0x0FFFFFFF),
        disabledForegroundColor: const Color(0xFF888888),
        textStyle: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Stance's `SessionEmptyCard`: 100 dp at white 4 %, "new session" in
/// the primary colour.
class _SessionEmptyCard extends StatelessWidget {
  const _SessionEmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      padding: const EdgeInsets.all(12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: StanceColors.cardFill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text.rich(
        const TextSpan(children: [
          TextSpan(text: 'Tap '),
          TextSpan(
              text: 'new session',
              style: TextStyle(color: StanceColors.primary)),
          TextSpan(text: ' to start collecting data.'),
        ]),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

/// Stance's `purple1` and `purple2` at 20 % (`ActiveCardBackground`).
const _purple1 = Color(0xFF915EEB);
const _purple2Tint = Color(0x33782EFD);

/// Compose's `Color.Gray`.
const _gray = Color(0xFF888888);

/// Stance's `SessionCard`: start date and a Continue/View pill, the tags
/// row, and the sets table (newest set first). The active session's card
/// is tinted purple with a 1 dp purple border.
class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.unit,
    required this.active,
    required this.onOpen,
  });

  final Session session;
  final WeightUnit unit;
  final bool active;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    return Material(
      key: ValueKey('sessionCard-${s.id}'),
      color: active ? _purple2Tint : StanceColors.cardFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: active ? const BorderSide(color: _purple1) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text(_detailedDate(s.startedAt), style: theme.textTheme.titleSmall),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _PillButton(
                    key: ValueKey('openSession-${s.id}'),
                    label: active ? 'Continue' : 'View',
                    onPressed: onOpen,
                  ),
                ),
              ),
            ]),
            SessionTagsRow(key: ValueKey('sessionTags-${s.id}'), tags: s.tags),
            if (s.sets.isNotEmpty) ...[
              const SizedBox(height: 10),
              _SetsTable(sets: s.sets.reversed.toList(), unit: unit),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Stance's `SessionDateFormatter.formatDateDetailed`: "17th October 26, 18:05".
String _detailedDate(DateTime t) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];
  final d = t.day;
  final suffix = d >= 11 && d <= 13
      ? 'th'
      : switch (d % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  final yy = (t.year % 100).toString().padLeft(2, '0');
  return '$d$suffix ${months[t.month - 1]} $yy, ${fmtTime(t)}';
}

/// Stance's `ExtraSmallPillButton`: purple1 text and a 12 dp arrow on
/// purple2 at 20 %.
class _PillButton extends StatelessWidget {
  const _PillButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _purple2Tint,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                maxLines: 1,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: _purple1, fontWeight: FontWeight.w600)),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_forward, size: 12, color: _purple1),
          ]),
        ),
      ),
    );
  }
}

/// Stance's `SessionSetsTable`: five equal columns (weight, reps, type,
/// RPE, speed) with grey labelSmall headers and semibold cells; the RPE
/// sits on a pill of its colour at 10 %.
class _SetsTable extends StatelessWidget {
  const _SetsTable({required this.sets, required this.unit});

  final List<SetRecord> sets;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cellStyle =
        theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600).tabular;
    Widget cell(String text, {double? rpe}) {
      final color = rpe == null ? null : rpeColor(rpe);
      final label = Text(text, style: cellStyle?.copyWith(color: color ?? Colors.white));
      if (color == null) {
        return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: label);
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: label,
      );
    }

    final columns = <(String, Widget Function(SetRecord))>[
      (
        'Weight (${unit.name})',
        (set) => cell(set.weight > 0
            ? fmtNumber(convertWeight(set.weight, set.unit, unit))
            : '--'),
      ),
      ('Reps', (set) => cell('${set.reps.length}')),
      ('Type', (set) => cell(set.setType?.shortName ?? '--')),
      ('RPE', (set) => cell(set.rpe == null ? '-' : fmtRpe(set.rpe), rpe: set.rpe)),
      (
        'Speed (m/s)',
        (set) => cell(set.reps.bestMeanVelocity?.toStringAsFixed(2) ?? '--'),
      ),
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (i, (title, build)) in columns.indexed) ...[
        if (i > 0) const SizedBox(width: 4),
        Expanded(
          child: Transform.translate(
            // Stance nudges the last column 5 dp left.
            offset: Offset(i == columns.length - 1 ? -5 : 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: _gray)),
                for (final set in sets) ...[
                  const SizedBox(height: 4),
                  build(set),
                ],
              ],
            ),
          ),
        ),
      ],
    ]);
  }
}
