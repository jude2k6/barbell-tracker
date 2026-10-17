/// Load–velocity chart data and same-weight history, ported from Stance's
/// `SessionChartRules` and `WeightPerformanceRules` (notes §12).
///
/// Stance plots raw points only: no regression, no 1RM projection.
library;

import 'dart:math' as math;

import '../analysis/exercises.dart';
import 'session.dart';

const lbPerKg = 2.2046226218;

/// Which rep's mean velocity represents a set.
enum SpeedChoice {
  /// Fastest rep (Stance's default).
  fastest,

  /// Last rep.
  last,
}

/// One set on the weight–velocity chart.
class LoadVelocityPoint {
  const LoadVelocityPoint(this.setIndex, this.weight, this.velocity);

  /// 0-based index into the session's sets.
  final int setIndex;

  /// Weight in the chart's unit.
  final double weight;

  /// Mean concentric velocity, m/s.
  final double velocity;
}

class LoadVelocityBounds {
  const LoadVelocityBounds(
      this.minWeight, this.maxWeight, this.minVelocity, this.maxVelocity);

  static const empty = LoadVelocityBounds(0, 1, 0, 1);

  final double minWeight, maxWeight, minVelocity, maxVelocity;
}

class LoadVelocityData {
  const LoadVelocityData(this.points, this.comparisonPoints, this.bounds);

  final List<LoadVelocityPoint> points;
  final List<LoadVelocityPoint> comparisonPoints;
  final LoadVelocityBounds bounds;

  bool get isEmpty => points.isEmpty && comparisonPoints.isEmpty;
}

/// Converts [weight] in [from] to [to].
double convertWeight(double weight, WeightUnit from, WeightUnit to) {
  if (from == to) return weight;
  return to == WeightUnit.lb ? weight * lbPerKg : weight / lbPerKg;
}

/// The velocity representing [set] under [choice], or null with no reps.
double? setVelocity(SetRecord set, SpeedChoice choice) {
  if (set.reps.isEmpty) return null;
  return switch (choice) {
    SpeedChoice.fastest =>
      set.reps.map((r) => r.meanVelocity).reduce(math.max),
    SpeedChoice.last => set.reps.last.meanVelocity,
  };
}

/// One point per set of [session] (and of [comparison], if given), in
/// [unit]. Sets with an analysis error, back-off sets, sets without a
/// weight and sets without reps are left out.
LoadVelocityData buildLoadVelocity(
  Session session, {
  required WeightUnit unit,
  Session? comparison,
  SpeedChoice choice = SpeedChoice.fastest,
}) {
  final points = _points(session, unit, choice);
  final comparisonPoints =
      comparison == null ? <LoadVelocityPoint>[] : _points(comparison, unit, choice);
  return LoadVelocityData(
      points, comparisonPoints, _bounds([...points, ...comparisonPoints]));
}

List<LoadVelocityPoint> _points(
    Session session, WeightUnit unit, SpeedChoice choice) {
  final out = <LoadVelocityPoint>[];
  for (final (i, set) in session.sets.indexed) {
    // Stance skips sets with analysis feedback; ours is analysisError.
    if (set.analysisError != null) continue;
    if (set.setType == SetType.backoff) continue;
    // Stance skips a null weight; ours stores a missing weight as 0.
    if (set.weight <= 0) continue;
    final v = setVelocity(set, choice);
    if (v == null) continue;
    out.add(LoadVelocityPoint(i, convertWeight(set.weight, set.unit, unit), v));
  }
  return out;
}

LoadVelocityBounds _bounds(List<LoadVelocityPoint> points) {
  if (points.isEmpty) return LoadVelocityBounds.empty;
  final w = points.map((p) => p.weight);
  final v = points.map((p) => p.velocity);
  return LoadVelocityBounds(
    math.max(w.reduce(math.min) * 0.9, 0),
    w.reduce(math.max) * 1.1,
    math.max(v.reduce(math.min) * 0.9, 0),
    v.reduce(math.max) * 1.1,
  );
}

/// One earlier set at the same weight: the spread of its rep velocities.
class WeightHistoryPoint {
  const WeightHistoryPoint(this.minVelocity, this.maxVelocity, this.date);

  final double minVelocity, maxVelocity;
  final DateTime date;
}

/// Stance's `MAX_POINTS`.
const weightHistoryMaxPoints = 12;

/// Stance's `EQUAL_RANGE_BUMP`, so a one-velocity set still shows a bar.
const _equalRangeBump = 0.1;

/// The last [weightHistoryMaxPoints] sets of [exerciseId] at exactly
/// [weight] in [unit], oldest first, across [sessions].
///
/// Like Stance, the weight must match exactly in the same unit (no
/// conversion) and back-off sets are included.
List<WeightHistoryPoint> buildWeightHistory(
  Iterable<Session> sessions, {
  required String exerciseId,
  required double weight,
  required WeightUnit unit,
}) {
  final sets = [
    for (final s in sessions)
      if (s.exerciseId == exerciseId)
        for (final set in s.sets)
          if (set.reps.isNotEmpty &&
              set.weight == weight &&
              set.unit == unit &&
              set.analysisError == null)
            set,
  ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final recent = sets.length > weightHistoryMaxPoints
      ? sets.sublist(sets.length - weightHistoryMaxPoints)
      : sets;
  return [for (final set in recent) _historyPoint(set)];
}

WeightHistoryPoint _historyPoint(SetRecord set) {
  final v = set.reps.map((r) => r.meanVelocity);
  final lo = v.reduce(math.min);
  var hi = v.reduce(math.max);
  if (hi == lo) hi += _equalRangeBump;
  return WeightHistoryPoint(lo, hi, set.startedAt);
}

/// Axis ticks at 1, 2, 5 or 10 × 10ⁿ spacing, about [count] of them
/// (Stance's `niceTicks`).
List<double> niceTicks(double min, double max, int count) {
  final raw = math.max(max - min, 1e-9) / math.max(count - 1, 1);
  final mag = math.pow(10, (math.log(raw) / math.ln10).floorToDouble()).toDouble();
  final f = raw / mag;
  final step = (f <= 1.5 ? 1 : f <= 3 ? 2 : f <= 7 ? 5 : 10) * mag;
  final ticks = <double>[];
  for (var t = (min / step).floorToDouble() * step;
      t <= max + 0.5 * step;
      t += step) {
    if (t >= min - 0.01 * step) ticks.add(t);
  }
  return ticks;
}
