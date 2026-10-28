import 'dart:math' as math;

import 'session.dart';

/// Stance's rep editing (notes §17): the 7-day edit window, "Recalculate"
/// to fewer reps, and Rep Check's markers on the velocity trace.

/// Stance's `SetEditWindowRules.EDIT_WINDOW_MS`.
const editWindow = Duration(days: 7);

/// Time left to edit [set]'s reps at [now]; zero once expired.
Duration editTimeLeft(SetRecord set, DateTime now) {
  final left = set.endedAt.add(editWindow).difference(now);
  return left.isNegative ? Duration.zero : left;
}

/// "Under 1 min", else the first two non-zero of days, hours, minutes,
/// e.g. "6d 23h", "5h 2m", "45m".
String formatTimeLeft(Duration d) {
  final minutes = d.inMinutes;
  if (minutes <= 0) return 'Under 1 min';
  final parts = [
    (minutes ~/ 1440, 'd'),
    ((minutes % 1440) ~/ 60, 'h'),
    (minutes % 60, 'm'),
  ].where((p) => p.$1 > 0).take(2);
  return parts.map((p) => '${p.$1}${p.$2}').join(' ');
}

/// Whether [set] has the velocity trace rep editing needs.
bool canEditReps(SetRecord set) =>
    set.velocityTrace.isNotEmpty && (set.traceHz ?? 0) > 0;

sealed class RecalculateResult {
  const RecalculateResult();
}

class Recalculated extends RecalculateResult {
  const Recalculated(this.set);
  final SetRecord set;
}

/// Only fewer reps can be found; [detected] is the current count.
class CanOnlyFindFewer extends RecalculateResult {
  const CanOnlyFindFewer(this.detected);
  final int detected;
}

class NoTrace extends RecalculateResult {
  const NoTrace();
}

/// Stance's `CorrectRepCountUseCase`: keeps [desired] reps by dropping the
/// ones with the smallest range of motion (a missing ROM counts as 0).
RecalculateResult recalculateReps(SetRecord set, int desired) {
  if (!canEditReps(set)) return const NoTrace();
  final n = set.reps.length;
  if (desired <= 0 || desired >= n) return CanOnlyFindFewer(n);
  final byRom = [for (var i = 0; i < n; i++) i]
    // List.sort isn't stable; tie-break on position as Kotlin's sortedWith.
    ..sort((a, b) {
      final c = (set.reps[a].romMeters ?? 0).compareTo(set.reps[b].romMeters ?? 0);
      return c != 0 ? c : a.compareTo(b);
    });
  final drop = byRom.take(n - desired).toSet();
  return Recalculated(set.copyWith(reps: _reindex([
    for (var i = 0; i < n; i++)
      if (!drop.contains(i)) set.reps[i],
  ])));
}

/// A rep's concentric start and end on the velocity trace, in seconds.
class RepMarker {
  const RepMarker(this.startSec, this.endSec);
  final double startSec, endSec;

  @override
  bool operator ==(Object other) =>
      other is RepMarker && other.startSec == startSec && other.endSec == endSec;

  @override
  int get hashCode => Object.hash(startSec, endSec);

  @override
  String toString() => 'RepMarker($startSec, $endSec)';
}

List<RepMarker> markersOf(SetRecord set) =>
    [for (final r in set.reps) RepMarker(r.startSec, r.endSec)];

/// The set's trace length in seconds (Stance's `SampleTimeAxis.durationSec`).
double traceDurationSec(SetRecord set) => set.velocityTrace.isEmpty
    ? 0
    : (set.velocityTrace.length - 1) / set.traceHz!;

/// Stance's `RepCheckSheet` constants: a marker is at least
/// [minRepDurationSec] long; the chart shows the reps plus [repCheckBufferSec]
/// either side, at most [repCheckWindowSec] at a time, and pans when the
/// scrubber comes within [repCheckEdgeSec] of a window edge.
const minRepDurationSec = 0.1;
const repCheckBufferSec = 5.0;
const repCheckWindowSec = 10.0;
const repCheckEdgeSec = 1.5;

/// Moves marker [i]'s start ([isStart]) or end to [t]: a start stays
/// between the previous rep's end (or 0) and its own end − 0.1 s; an end
/// between its own start + 0.1 s and the next rep's start (or [durationSec]).
/// Unchanged when the neighbours leave no room.
List<RepMarker> moveMarker(List<RepMarker> markers, int i,
    {required bool isStart, required double t, required double durationSec}) {
  final m = markers[i];
  final (lo, hi) = isStart
      ? (i > 0 ? markers[i - 1].endSec : 0.0, m.endSec - minRepDurationSec)
      : (
          m.startSec + minRepDurationSec,
          i < markers.length - 1 ? markers[i + 1].startSec : durationSec,
        );
  if (hi < lo) return markers;
  final v = t.clamp(lo, hi).toDouble();
  return [...markers]
    ..[i] = isStart ? RepMarker(v, m.endSec) : RepMarker(m.startSec, v);
}

/// The part of the trace Rep Check shows (Stance's `RepCheckSheet`): the
/// reps plus 5 s either side, clamped to the trace. Longer than 10 s, it
/// shows a 10 s window starting at a movable `windowStart`.
class RepCheckRange {
  RepCheckRange(List<RepMarker> markers, double durationSec)
      : dataStart = markers.isEmpty
            ? 0
            : math.max(markers.first.startSec - repCheckBufferSec, 0),
        dataEnd = math.min(
            (markers.isEmpty ? durationSec : markers.last.endSec) +
                repCheckBufferSec,
            durationSec);

  final double dataStart, dataEnd;

  bool get scrolls => dataEnd - dataStart > repCheckWindowSec;

  /// The latest window start.
  double get maxWindowStart =>
      math.max(dataEnd - repCheckWindowSec, dataStart);

  /// Where the window starts on opening: centred on the middle of
  /// [original]'s reps.
  double initialWindowStart(List<RepMarker> original) {
    final mid = original.isEmpty
        ? dataStart
        : (original.first.startSec + original.last.endSec) / 2;
    return (mid - repCheckBufferSec).clamp(dataStart, maxWindowStart).toDouble();
  }

  /// The visible (start, end) for [windowStart].
  (double, double) visible(double windowStart) => scrolls
      ? (windowStart, windowStart + repCheckWindowSec)
      : (dataStart, dataEnd);

  /// Stance's `applyScrub`: the scrubber moves to [t] within the visible
  /// window; within 1.5 s of an edge with more trace beyond, the window
  /// pans by the shortfall.
  ({double scrub, double windowStart}) scrub(double t, double windowStart) {
    final (lo, hi) = visible(windowStart);
    final s = t.clamp(lo, hi).toDouble();
    if (!scrolls) return (scrub: s, windowStart: windowStart);
    var ws = windowStart;
    if (hi - s < repCheckEdgeSec && hi < dataEnd) {
      ws = (ws + repCheckEdgeSec - (hi - s))
          .clamp(dataStart, maxWindowStart)
          .toDouble();
    } else if (s - lo < repCheckEdgeSec && lo > dataStart) {
      ws = (ws - (repCheckEdgeSec - (s - lo)))
          .clamp(dataStart, maxWindowStart)
          .toDouble();
    }
    return (scrub: s, windowStart: ws);
  }
}

enum AddTimeError { startInside, endInside, encompass, overlap, endBeforeStart }

/// Stance's `validateAddTime` for a new rep's start ([isStart]) or end
/// ([start] given); null when [t] is acceptable. The error's rep number is
/// 1-based.
(AddTimeError, int)? validateAddTime(List<RepMarker> markers, double t,
    {required bool isStart, double? start}) {
  if (!isStart && start != null && t <= start) {
    return (AddTimeError.endBeforeStart, 0);
  }
  for (final (i, m) in markers.indexed) {
    if (t > m.startSec && t < m.endSec) {
      return (isStart ? AddTimeError.startInside : AddTimeError.endInside, i + 1);
    }
    if (!isStart && start != null) {
      if (start < m.startSec && t > m.endSec) return (AddTimeError.encompass, i + 1);
      if (start > m.startSec && start < m.endSec) return (AddTimeError.overlap, i + 1);
    }
  }
  return null;
}

String addTimeErrorText((AddTimeError, int) e) => switch (e.$1) {
      AddTimeError.startInside => 'Start time cannot be inside Rep ${e.$2}',
      AddTimeError.endInside => 'End time cannot be inside Rep ${e.$2}',
      AddTimeError.encompass => 'New rep cannot encompass Rep ${e.$2}',
      AddTimeError.overlap => 'New rep cannot overlap with Rep ${e.$2}',
      AddTimeError.endBeforeStart => 'End time must be after start time',
    };

/// Stance's `EditRepMarkersUseCase`: rebuilds [set]'s reps from [markers].
/// Mean and peak come from the trace between each marker's start and end;
/// ROM and sticking region survive only on markers left unmoved. Null when
/// a marker ends before it starts or the set has no trace.
SetRecord? applyRepMarkers(SetRecord set, List<RepMarker> markers) {
  if (!canEditReps(set)) return null;
  if (markers.any((m) => m.endSec <= m.startSec)) return null;
  final v = set.velocityTrace;
  final hz = set.traceHz!;
  final duration = traceDurationSec(set);
  int indexAt(double sec) => (sec * hz).floor().clamp(0, v.length - 1);

  final sorted = [...markers]..sort((a, b) => a.startSec.compareTo(b.startSec));
  return set.copyWith(reps: _reindex([
    for (final m in sorted)
      () {
        final from = indexAt(m.startSec);
        final to = (m.endSec >= duration ? v.length : indexAt(m.endSec))
            .clamp(from, v.length);
        final slice = v.sublist(from, to);
        final same = set.reps
            .where((r) => r.startSec == m.startSec && r.endSec == m.endSec)
            .firstOrNull;
        return RepRecord(
          index: 0,
          startSec: m.startSec,
          endSec: m.endSec,
          meanVelocity:
              slice.isEmpty ? 0 : slice.reduce((a, b) => a + b) / slice.length,
          peakVelocity: slice.isEmpty ? 0 : slice.reduce(math.max),
          // Stance stores ROM 0 for a moved rep; unknown (null) shows "–".
          romMeters: same?.romMeters,
          sticking: same?.sticking,
        );
      }(),
  ]));
}

List<RepRecord> _reindex(List<RepRecord> reps) => [
      for (final (i, r) in reps.indexed)
        RepRecord(
          index: i + 1,
          startSec: r.startSec,
          endSec: r.endSec,
          meanVelocity: r.meanVelocity,
          peakVelocity: r.peakVelocity,
          romMeters: r.romMeters,
          sticking: r.sticking,
        ),
    ];
