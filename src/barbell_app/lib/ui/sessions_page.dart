import 'package:flutter/material.dart';

import '../analysis/exercises.dart';
import '../workout/active_session.dart';
import '../workout/load_velocity.dart';
import '../workout/preferences.dart';
import '../workout/session.dart';
import '../workout/set_metrics.dart';
import 'app_scope.dart';
import 'format.dart';
import 'permission_prompts.dart';
import 'session_tag_editor.dart';
import 'sensor_status_chip.dart';
import 'sessions_builder.dart';
import 'workout_flow.dart';

/// Stance's Sessions screen for one exercise: "New Session", then a card
/// per session, newest first. The newest session is continuable for an
/// hour after its last set (`activeSessionId`); its card says Continue,
/// the others View.
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
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          SensorStatusChip(sensor: app.sensor, onPressed: () => openDevice(context)),
          const SizedBox(width: 8),
        ],
      ),
      body: SessionsBuilder(
        store: app.sessions,
        builder: (context, all) {
          if (all == null) return const Center(child: CircularProgressIndicator());
          final sessions = [
            for (final s in all)
              if (s.exerciseId == exercise.id) s,
          ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
          final active = activeSessionId(sessions, exercise.id, now: now?.call());
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(exercise.rawValue, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('newSession'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.add),
                label: const Text('New Session'),
                onPressed: () => _newSession(context, exercise),
              ),
              const SizedBox(height: 16),
              if (sessions.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Text('No sessions yet for this exercise.',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      const Text('Tap new session to start collecting data.'),
                    ]),
                  ),
                ),
              for (final s in sessions)
                _SessionCard(
                  session: s,
                  unit: unit,
                  active: s.id == active,
                  onOpen: () => openSessionFeedback(context, s, active: s.id == active),
                ),
            ],
          );
        },
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

/// Date and time range, day type, set and rep counts, average bar speed, and a row
/// per set (newest first): type, weight, reps, fastest rep speed, RPE.
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
    final avg = s.sets.expand((set) => set.reps).toList().avgMeanVelocity;
    final head = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final body = theme.textTheme.bodySmall.tabular;
    Widget cell(String t, TextStyle? style) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(t, style: style),
        );

    return Card(
      key: ValueKey('sessionCard-${s.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(
                  '${fmtDate(s.startedAt)} · ${fmtTime(s.startedAt)} – '
                  '${fmtTime(sessionEnd(s))}',
                  style: theme.textTheme.titleSmall.tabular,
                ),
              ),
              FilledButton.tonal(
                key: ValueKey('openSession-${s.id}'),
                onPressed: onOpen,
                child: Text(active ? 'Continue' : 'View'),
              ),
            ]),
            SessionTagsRow(key: ValueKey('sessionTags-${s.id}'), tags: s.tags),
            Text(
              '${s.sets.length} sets · ${s.totalReps} reps'
              '${avg == null ? '' : ' · Avg bar speed: ${fmtVelocity(avg)} m/s'}',
              style: theme.textTheme.bodySmall.tabular,
            ),
            if (s.sets.isNotEmpty) ...[
              const SizedBox(height: 8),
              Table(
                columnWidths: const {0: FlexColumnWidth(0.8)},
                children: [
                  TableRow(children: [
                    for (final h in ['Type', 'Weight', 'Reps', 'Speed', 'RPE'])
                      cell(h, head),
                  ]),
                  for (final set in s.sets.reversed)
                    TableRow(children: [
                      cell(set.setType?.shortName ?? '--', body),
                      cell(
                          set.weight > 0
                              ? fmtWeight(
                                  convertWeight(set.weight, set.unit, unit), unit)
                              : '--',
                          body),
                      cell('${set.reps.length}', body),
                      cell(fmtVelocity(set.reps.bestMeanVelocity ?? 0), body),
                      cell(set.rpe == null ? '-' : fmtRpe(set.rpe), body),
                    ]),
                ],
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
