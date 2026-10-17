/// RPE learning: the per-exercise speed–intensity profile, ported from
/// Stance's `BuildRpeIntensityProfileUseCase` and
/// `BuildRpeProfileGroupsUseCase` (notes §13).
///
/// Each set the user tagged with an RPE contributes its last rep's mean
/// velocity. Velocities are grouped by RPE and summarised by their
/// interquartile range. Given a new set's last-rep speed, the profile
/// suggests the RPE range whose past speeds overlap it (±20 %).
library;

import 'dart:math' as math;

import 'session.dart';

/// Velocities logged at one RPE.
class RpeIntensityPoint {
  const RpeIntensityPoint({
    required this.rpe,
    required this.minVelocity,
    required this.maxVelocity,
    required this.absoluteMin,
    required this.absoluteMax,
    required this.velocities,
  });

  final double rpe;

  /// Interquartile range of [velocities], m/s.
  final double minVelocity, maxVelocity;
  final double absoluteMin, absoluteMax;

  /// Last-rep mean velocities of every set tagged with [rpe].
  final List<double> velocities;
}

class RpeIntensityProfile {
  const RpeIntensityProfile({
    required this.points,
    required this.lastRepSpeed,
    required this.minRpe,
    required this.maxRpe,
    required this.minSpeed,
    required this.maxSpeed,
  });

  /// Sorted by RPE.
  final List<RpeIntensityPoint> points;

  /// The set being rated, if any.
  final double? lastRepSpeed;

  /// RPE range whose speeds overlap the window (7–9 when unknown).
  final double minRpe, maxRpe;

  /// Speed window: [lastRepSpeed] ± 20 % (0–1 when unknown).
  final double minSpeed, maxSpeed;

  bool get isEmpty => points.isEmpty;

  /// True when [minRpe]–[maxRpe] came from matching points, not defaults.
  bool get hasSuggestion =>
      lastRepSpeed != null &&
      points.any((p) => p.maxVelocity >= minSpeed && p.minVelocity <= maxSpeed);
}

/// Stance's speed window half-width, as a fraction of the last-rep speed.
const _windowFraction = 0.2;

/// Stance's bar height for a degenerate quartile range, m/s.
const _minBand = 0.02;

/// Last rep's mean velocity, or null if there are no reps or it is not
/// positive (Stance stores missing velocities as 0).
double? lastRepSpeed(SetRecord set) {
  if (set.reps.isEmpty) return null;
  final v = set.reps.last.meanVelocity;
  return v > 0 ? v : null;
}

/// The profile for [exerciseId] across [sessions], with the window around
/// [speed] (the last-rep speed of the set being rated).
RpeIntensityProfile buildRpeProfile(
  Iterable<Session> sessions, {
  required String exerciseId,
  double? speed,
}) {
  final byRpe = <double, List<double>>{};
  for (final s in sessions) {
    if (s.exerciseId != exerciseId) continue;
    for (final set in s.sets) {
      // Stance skips sets with feedback; ours is analysisError.
      if (set.analysisError != null) continue;
      final rpe = set.rpe;
      final v = lastRepSpeed(set);
      if (rpe == null || v == null) continue;
      byRpe.putIfAbsent(rpe, () => []).add(v);
    }
  }
  final points = [
    for (final MapEntry(key: rpe, value: v) in byRpe.entries)
      if (velocityRangeFromQuartiles(v) case (final lo, final hi))
        RpeIntensityPoint(
          rpe: rpe,
          minVelocity: lo,
          maxVelocity: hi,
          absoluteMin: v.reduce(math.min),
          absoluteMax: v.reduce(math.max),
          velocities: v,
        ),
  ]..sort((a, b) => a.rpe.compareTo(b.rpe));
  return _window(points, speed);
}

RpeIntensityProfile _window(List<RpeIntensityPoint> points, double? speed) {
  var minSpeed = 0.0, maxSpeed = 1.0, minRpe = 7.0, maxRpe = 9.0;
  if (speed != null) {
    if (speed >= 0) {
      final d = speed * _windowFraction;
      final lo = math.max(0.0, speed - d), hi = speed + d;
      if (hi > lo) {
        minSpeed = lo;
        maxSpeed = hi;
      }
    }
    if (points.isNotEmpty) {
      bool overlaps(RpeIntensityPoint p) =>
          p.maxVelocity >= minSpeed && p.minVelocity <= maxSpeed;
      minRpe = math.max(5, points.where(overlaps).firstOrNull?.rpe ?? 7);
      maxRpe = math.min(10, points.where(overlaps).lastOrNull?.rpe ?? 9);
    }
  }
  return RpeIntensityProfile(
    points: points,
    lastRepSpeed: speed,
    minRpe: minRpe,
    maxRpe: maxRpe,
    minSpeed: minSpeed,
    maxSpeed: maxSpeed,
  );
}

/// The 25th–75th percentile range of [velocities], widened to
/// [_minBand] when it collapses. Null when empty.
(double, double)? velocityRangeFromQuartiles(List<double> velocities) {
  if (velocities.isEmpty) return null;
  final sorted = [...velocities]..sort();
  if (sorted.length == 1) return (sorted[0], sorted[0] + _minBand);
  final q1 = percentile(sorted, 0.25), q3 = percentile(sorted, 0.75);
  if (q3 <= q1) {
    final mid = (q1 + q3) / 2;
    return (mid, mid + _minBand);
  }
  return (q1, q3);
}

/// Linear-interpolated percentile of an ascending list, `p` in 0–1.
double percentile(List<double> sorted, double p) {
  final pos = p * (sorted.length - 1);
  final i = pos.floor();
  final next = sorted[math.min(i + 1, sorted.length - 1)];
  return sorted[i] + (pos - i) * (next - sorted[i]);
}

// --- profile manager ---

/// One RPE-tagged set, for reviewing and editing the profile.
class RpeProfileRow {
  const RpeProfileRow({
    required this.sessionId,
    required this.setId,
    required this.rpe,
    required this.weight,
    required this.unit,
    required this.lastRepSpeed,
    required this.date,
  });

  final String sessionId, setId;
  final double rpe;
  final double weight;
  final WeightUnit unit;
  final double? lastRepSpeed;
  final DateTime date;
}

class RpeProfileGroup {
  const RpeProfileGroup(this.rpe, this.rows);
  final double rpe;
  final List<RpeProfileRow> rows;
}

/// Row order within a group; all descending, as in Stance.
enum RpeProfileSort {
  date('Date'),
  speed('Speed'),
  weight('Weight');

  const RpeProfileSort(this.label);
  final String label;
}

/// Every RPE-tagged set of [exerciseId], grouped by RPE (ascending).
///
/// Unlike the profile itself, rows without a usable last-rep speed are
/// kept so their tags can still be edited or removed.
List<RpeProfileGroup> buildRpeGroups(
  Iterable<Session> sessions, {
  required String exerciseId,
  RpeProfileSort sort = RpeProfileSort.date,
}) {
  final byRpe = <double, List<RpeProfileRow>>{};
  for (final s in sessions) {
    if (s.exerciseId != exerciseId) continue;
    for (final set in s.sets) {
      final rpe = set.rpe;
      if (set.analysisError != null || rpe == null) continue;
      byRpe.putIfAbsent(rpe, () => []).add(RpeProfileRow(
            sessionId: s.id,
            setId: set.id,
            rpe: rpe,
            weight: set.weight,
            unit: set.unit,
            lastRepSpeed: set.reps.isEmpty ? null : set.reps.last.meanVelocity,
            date: set.startedAt,
          ));
    }
  }
  int desc(double? a, double? b) =>
      (b ?? double.negativeInfinity).compareTo(a ?? double.negativeInfinity);
  final compare = switch (sort) {
    RpeProfileSort.date => (RpeProfileRow a, RpeProfileRow b) =>
        b.date.compareTo(a.date),
    RpeProfileSort.speed => (RpeProfileRow a, RpeProfileRow b) =>
        desc(a.lastRepSpeed, b.lastRepSpeed),
    // Stance compares raw weights without unit conversion.
    RpeProfileSort.weight => (RpeProfileRow a, RpeProfileRow b) =>
        desc(a.weight, b.weight),
  };
  return [
    for (final MapEntry(key: rpe, value: rows) in byRpe.entries)
      RpeProfileGroup(rpe, rows..sort(compare)),
  ]..sort((a, b) => a.rpe.compareTo(b.rpe));
}
