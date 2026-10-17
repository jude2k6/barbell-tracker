/// Set and session comparison, ported from Stance's comparison section,
/// `SessionsRepositoryImpl.getAvailableComparisonDates` /
/// `getSessionForComparison` and the session feedback mapper (notes §15).
library;

import 'dart:math' as math;

import 'load_velocity.dart';
import 'session.dart';
import 'session_tags.dart';

/// Earlier sessions of [current]'s exercise that can be compared against:
/// one per calendar day, newest day first. For a day with several
/// sessions, the earliest one stands for it.
///
/// Only sessions with the same session type (day type) qualify, and a
/// session without one gets none, as in Stance.
List<Session> comparisonCandidates(
    Iterable<Session> sessions, Session current) {
  // Stance offers nothing for a session without a type, and otherwise
  // only sessions of the same type.
  final type = sessionTypeOf(current.tags);
  if (type.isEmpty) return const [];
  final byDay = <DateTime, Session>{};
  for (final s in sessions) {
    if (s.id == current.id ||
        s.exerciseId != current.exerciseId ||
        !s.startedAt.isBefore(current.startedAt) ||
        sessionTypeOf(s.tags) != type) {
      continue;
    }
    final t = s.startedAt.toLocal();
    final day = DateTime(t.year, t.month, t.day);
    final seen = byDay[day];
    if (seen == null || s.startedAt.isBefore(seen.startedAt)) byDay[day] = s;
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final d in days) byDay[d]!];
}

/// One row of the comparison table.
class ComparisonTableRow {
  const ComparisonTableRow({
    required this.setIndex,
    required this.type,
    required this.weight,
    required this.unit,
    required this.reps,
    required this.speed,
    required this.rpe,
  });

  final int setIndex;

  /// Set type short name, or "--".
  final String type;
  final double weight;
  final WeightUnit unit;
  final int reps;

  /// `%.2f` of the chosen rep speed; "0.00" without reps, as in Stance.
  final String speed;

  /// RPE, or "-".
  final String rpe;
}

/// Every set of [session] as a table row, with the speed per [choice].
List<ComparisonTableRow> comparisonTable(Session session, SpeedChoice choice) => [
      for (final (i, set) in session.sets.indexed)
        ComparisonTableRow(
          setIndex: i,
          type: set.setType?.shortName ?? '--',
          weight: set.weight,
          unit: set.unit,
          reps: set.reps.length,
          speed: (setVelocity(set, choice) ?? 0).toStringAsFixed(2),
          rpe: set.rpe == null ? '-' : _fmtRpe(set.rpe!),
        ),
    ];

String _fmtRpe(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Shared y range for the per-set rep speed charts: positive rep mean
/// velocities across [sets], padded by 10 % (0–1 when there are none).
(double, double) repSpeedBounds(List<SetRecord> sets) {
  final v = [
    for (final s in sets)
      for (final r in s.reps)
        if (r.meanVelocity > 0) r.meanVelocity,
  ];
  if (v.isEmpty) return (0, 1);
  final lo = math.max(v.reduce(math.min) * 0.9, 0.0);
  final hi = math.max(v.reduce(math.max) * 1.1, lo + 1e-9);
  return (lo, hi);
}

/// Sets a set's rep chart can be compared with: every other set of the
/// session, most recent first.
List<int> compareSetOptions(Session session, int setIndex) => [
      for (var i = session.sets.length - 1; i >= 0; i--)
        if (i != setIndex) i,
    ];

/// Y range for one rep chart (Stance's `RepVelocityChart`): from 10 %
/// below the lowest positive value to 10 % above the highest.
(double, double) repChartBounds(List<double> values) {
  final positive = values.where((v) => v > 0);
  final lo = positive.isEmpty ? 0.0 : positive.reduce(math.min) * 0.9;
  final top = values.isEmpty ? 1.0 : values.reduce(math.max) * 1.1;
  return (lo, top > lo ? top : lo + 1);
}
