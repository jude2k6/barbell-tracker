/// Port of the reference app's Kotlin `SquatBenchSensorMotionMapper` and
/// `TimestampRescaler` (notes §9): valid-sample filter, sensor-clock
/// timeline, gap repair and host-clock rescale.
library;

import '../sensor/sensor_sample.dart';

class MappedMotion {
  MappedMotion(this.timeSec, this.samples, {this.rescaleFactor = 1});

  /// Seconds from the first valid sample.
  final List<double> timeSec;
  final List<SensorSample> samples;
  final double rescaleFactor;

  int get length => samples.length;
}

class MotionMapper {
  static const repairGapThresholdSec = 2.0;
  static const fallbackDtSec = 0.005;

  static bool _validImu(SensorSample s) =>
      (s.q0 != 0 || s.q1 != 0 || s.q2 != 0 || s.q3 != 0) &&
      (s.ax != 0 || s.ay != 0 || s.az != 0);

  static MappedMotion map(List<SensorSample> input) {
    final valid = input.where(_validImu).toList();
    if (valid.isEmpty) {
      throw ArgumentError('All sensor samples had zero quaternion/accelerometer');
    }

    // Sensor clock relative to the first sample with one; host clock otherwise.
    final firstSensor = valid
        .map((s) => s.sensorTimeMs)
        .firstWhere((t) => t != null, orElse: () => null);
    final firstHostMs = valid.first.hostTimeUs / 1000.0;
    final raw = [
      for (final s in valid)
        (firstSensor != null && s.sensorTimeMs != null
                ? (s.sensorTimeMs! - firstSensor).toDouble()
                : s.hostTimeUs / 1000.0 - firstHostMs) /
            1000.0,
    ];

    var t = _repairTimeline(raw);

    final hostSpan = (valid.last.hostTimeUs - valid.first.hostTimeUs) / 1e6;
    if (firstSensor == null || hostSpan <= 0) return MappedMotion(t, valid);

    // Stretch the sensor timeline to the phone's span.
    final span = t.last - t.first;
    if (span <= 0) return MappedMotion(t, valid);
    final factor = hostSpan / span;
    if (factor < 0.5 || factor > 2.0) {
      // Clocks disagree badly: fall back to a uniform host timeline.
      final n = t.length;
      t = [for (var i = 0; i < n; i++) n <= 1 ? 0.0 : i * hostSpan / (n - 1)];
    } else if (factor != 1.0) {
      final t0 = t.first;
      t = [for (final x in t) (x - t0) * factor + t0];
    }
    return MappedMotion(t, valid, rescaleFactor: factor);
  }

  /// Replace non-positive or >2 s steps with the median good step.
  static List<double> _repairTimeline(List<double> t) {
    if (t.length < 2) return t;
    final good = <double>[];
    var bad = 0;
    for (var i = 1; i < t.length; i++) {
      final dt = t[i] - t[i - 1];
      if (dt <= 0 || dt > repairGapThresholdSec) {
        bad++;
      } else {
        good.add(dt);
      }
    }
    if (bad == 0 && t.first == 0) return t;
    good.sort();
    final dtFix = good.isEmpty ? fallbackDtSec : good[good.length ~/ 2];
    final out = [0.0];
    for (var i = 1; i < t.length; i++) {
      var dt = t[i] - t[i - 1];
      if (dt <= 0 || dt > repairGapThresholdSec) dt = dtFix;
      out.add(out.last + dt);
    }
    return out;
  }
}
