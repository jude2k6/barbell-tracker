import '../workout/session.dart';

/// What the video overlay shows at one instant.
class OverlayFrame {
  const OverlayFrame({
    required this.sensorSec,
    required this.repsDone,
    this.activeRep,
    this.lastRep,
    this.velocity,
  });

  /// Position on the sensor time base.
  final double sensorSec;

  /// Reps whose concentric phase has finished.
  final int repsDone;

  /// Rep whose concentric phase contains [sensorSec], if any.
  final RepRecord? activeRep;

  /// Most recently finished rep, if any.
  final RepRecord? lastRep;

  /// Bar velocity at [sensorSec], m/s, if a trace is stored.
  final double? velocity;

  /// The rep to headline: the one in progress, else the last finished.
  RepRecord? get headline => activeRep ?? lastRep;
}

/// Maps video time to sensor time for one set and looks up rep state.
///
/// Video time = sensor time + [offsetSec] (see `SetRecord.videoOffsetSec`).
/// The reference app's `RepOverlayWindow` carries the same information:
/// rep number, window, mean velocity and orange sticking band.
class OverlayTimeline {
  OverlayTimeline(this.set, {double? offsetSec})
      : offsetSec = offsetSec ?? set.videoOffsetSec ?? 0;

  final SetRecord set;
  final double offsetSec;

  double sensorTime(Duration videoPosition) =>
      videoPosition.inMicroseconds / 1e6 - offsetSec;

  Duration videoPosition(double sensorSec) =>
      Duration(microseconds: ((sensorSec + offsetSec) * 1e6).round());

  OverlayFrame at(Duration videoPosition) {
    final t = sensorTime(videoPosition);
    RepRecord? active, last;
    var done = 0;
    for (final r in set.reps) {
      if (t >= r.startSec && t <= r.endSec) active = r;
      if (t > r.endSec) {
        done++;
        last = r;
      }
    }
    return OverlayFrame(
      sensorSec: t,
      repsDone: done,
      activeRep: active,
      lastRep: last,
      velocity: _velocityAt(t),
    );
  }

  double? _velocityAt(double t) {
    final v = set.velocityTrace;
    final hz = set.traceHz;
    if (v.isEmpty || hz == null || hz <= 0) return null;
    final x = t * hz;
    if (x < 0 || x > v.length - 1) return null;
    final i = x.floor();
    if (i >= v.length - 1) return v.last;
    final f = x - i;
    return v[i] * (1 - f) + v[i + 1] * f;
  }

  /// Where to jump to watch [rep]: one second before its concentric phase.
  Duration seekTarget(RepRecord rep) {
    final d = videoPosition(rep.startSec - 1);
    return d.isNegative ? Duration.zero : d;
  }
}
