/// Readiness: today's set speed against earlier sessions at the same weight,
/// ported from Stance's `HistoricalDataRepositoryImpl`,
/// `FetchSessionReadinessUseCase` and the readiness UI mapper (notes §14).
library;

import 'dart:math' as math;

import '../analysis/exercises.dart';
import 'session.dart';
import 'session_tags.dart';

/// One earlier session's speed at the same weight.
class ReadinessPoint {
  const ReadinessPoint(this.speed, this.date, [this.sessionLabel = '']);

  /// Fastest rep mean velocity of the session's first matching set, m/s.
  final double speed;
  final DateTime date;

  /// The session's Block and Week tags, e.g. `Block:2 Week:3`
  /// ([readinessSessionLabel]).
  final String sessionLabel;
}

class ReadinessResult {
  const ReadinessResult({
    required this.lastSessionSpeed,
    required this.historicAverage,
    required this.points,
  });

  static const empty =
      ReadinessResult(lastSessionSpeed: null, historicAverage: null, points: []);

  /// The most recent matching session.
  final double? lastSessionSpeed;

  /// Mean over all matching sessions (including the last one); null with
  /// fewer than two.
  final double? historicAverage;

  /// Newest first; empty with fewer than two sessions (Stance hides the
  /// history then).
  final List<ReadinessPoint> points;

  bool get hasHistory => lastSessionSpeed != null;
}

/// Stance's query defaults.
const readinessMaxDaysBack = 90;
const readinessMaxResults = 12;

/// This set's speed for readiness: its fastest rep mean velocity.
double? readinessSpeed(SetRecord set) => set.reps.isEmpty
    ? null
    : set.reps.map((r) => r.meanVelocity).reduce(math.max);

/// Earlier sessions of [current]'s exercise where [set]'s weight was
/// lifted, within [readinessMaxDaysBack] days, newest first.
///
/// Per session, only the first set at the same weight, without an analysis
/// error and of a compatible set type, counts.
ReadinessResult buildReadiness(
  Iterable<Session> sessions, {
  required Session current,
  required SetRecord set,
}) {
  if (set.weight <= 0) return ReadinessResult.empty;
  final cutoff =
      current.startedAt.subtract(const Duration(days: readinessMaxDaysBack));
  final entries = <ReadinessPoint>[];
  for (final s in sessions) {
    if (s.id == current.id ||
        s.exerciseId != current.exerciseId ||
        !s.startedAt.isBefore(current.startedAt) ||
        s.startedAt.isBefore(cutoff)) {
      continue;
    }
    // Same session type ("" matches only other untagged sessions).
    if (sessionTypeOf(s.tags) != sessionTypeOf(current.tags)) continue;
    final match = s.sets.where((h) => _matches(h, set)).firstOrNull;
    final speed = match == null ? null : readinessSpeed(match);
    if (speed != null) {
      entries.add(
          ReadinessPoint(speed, s.startedAt, readinessSessionLabel(s.tags)));
    }
  }
  if (entries.isEmpty) return ReadinessResult.empty;
  entries.sort((a, b) => b.date.compareTo(a.date));
  final recent = entries.take(readinessMaxResults).toList();
  final several = recent.length >= 2;
  return ReadinessResult(
    lastSessionSpeed: recent.first.speed,
    historicAverage: several
        ? recent.map((e) => e.speed).reduce((a, b) => a + b) / recent.length
        : null,
    points: several ? recent : const [],
  );
}

bool _matches(SetRecord historical, SetRecord current) =>
    historical.weight == current.weight &&
    // Stance compares the bare number; we also require the same unit.
    historical.unit == current.unit &&
    historical.analysisError == null &&
    setTypesCompatible(current.setType, historical.setType);

/// Stance's `SetTypeTagCompatibility`: warm-ups, last warm-ups and top sets
/// compare with each other; back-off only with back-off; untagged only
/// with untagged.
bool setTypesCompatible(SetType? current, SetType? historical) {
  if (current == null) return historical == null;
  if (historical == null) return false;
  const warmUpGroup = {SetType.warmUp, SetType.lastWarmUp, SetType.topSet};
  if (warmUpGroup.contains(current) && warmUpGroup.contains(historical)) {
    return true;
  }
  return current == historical;
}

/// "Faster"/"Slower" verdict shown above the readiness numbers.
class ReadinessComparison {
  const ReadinessComparison(this.title, this.description, this.isFaster);
  final String title, description;
  final bool isFaster;
}

/// Stance's threshold: a difference counts at ≥ 0.05 m/s or ≥ 5 %.
bool _significant(double a, double b) {
  final d = (a - b).abs();
  return d >= 0.05 || d / b >= 0.05;
}

/// Compares [current] with last session and the average. Null when there
/// is nothing to compare, the differences are small, they disagree, or
/// the set is a warm-up or back-off. [weightLabel] is e.g. "100 kg".
ReadinessComparison? compareReadiness({
  required double current,
  required double? lastSession,
  required double? average,
  required SetType? setType,
  required String weightLabel,
}) {
  final last = lastSession ?? 0, avg = average ?? 0;
  if (current <= 0 || (last <= 0 && avg <= 0)) return null;
  final fasterThanLast = last <= 0 || current > last;
  final fasterThanAvg = avg <= 0 || current > avg;
  final slowerThanLast = last > 0 && current < last;
  final slowerThanAvg = avg > 0 && current < avg;

  final against = <String>[];
  var faster = false, slower = false;
  if (last > 0 && _significant(current, last)) {
    if (fasterThanLast) {
      against.add('Last Session');
      faster = true;
    } else if (slowerThanLast) {
      against.add('Last Session');
      slower = true;
    }
  }
  if (avg > 0 && _significant(current, avg)) {
    final hasLast = against.contains('Last Session');
    if (fasterThanAvg) {
      if (!hasLast || fasterThanLast) {
        against.add('Historical Average');
        faster = true;
      }
    } else if (slowerThanAvg && (!hasLast || slowerThanLast)) {
      against.add('Historical Average');
      slower = true;
    }
  }
  if (against.isEmpty || (faster && slower)) return null;
  if (setType == SetType.warmUp || setType == SetType.backoff) return null;
  final what = against.join(' and ');
  return faster
      ? ReadinessComparison(
          'Faster', '$weightLabel moved faster than $what.', true)
      : ReadinessComparison(
          'Slower', '$weightLabel moved slower than $what.', false);
}

/// Stance's `daysAgoText`, by calendar day in local time.
String daysAgoText(DateTime date, DateTime reference) {
  DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
  final days =
      (day(reference.toLocal()).difference(day(date.toLocal())).inHours / 24)
          .round();
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  if (days < 14) return '1 week ago';
  if (days < 30) return '${days ~/ 7} weeks ago';
  if (days < 60) return '1 month ago';
  return '${days ~/ 30} months ago';
}
