import 'sensor_sample.dart';

/// Measures the sample rate actually delivered over BLE, using the sensor's
/// own clock where available, and counts samples that never arrived.
///
/// This answers the open question from the reverse-engineering notes: the
/// reference pipelines assume 200 Hz, but nobody checked what arrives.
class RateMonitor {
  RateMonitor({this.nominalHz = 200, this.window = const Duration(seconds: 2)});

  final double nominalHz;
  final Duration window;

  final _times = <int>[]; // ms, sensor clock if present else host clock
  int? _lastMs;

  int received = 0;
  int estimatedMissing = 0;
  int clockJumps = 0;

  void add(SensorSample s) {
    final ms = s.sensorTimeMs ?? s.hostTimeUs ~/ 1000;
    received++;
    final last = _lastMs;
    if (last != null) {
      final dt = ms - last;
      final expected = 1000 / nominalHz;
      if (dt <= 0 || dt > 2000) {
        clockJumps++; // matches the reference app's gap-repair rule
      } else if (dt > 1.5 * expected) {
        estimatedMissing += (dt / expected).round() - 1;
      }
    }
    _lastMs = ms;
    _times.add(ms);
    final cutoff = ms - window.inMilliseconds;
    while (_times.isNotEmpty && _times.first < cutoff) {
      _times.removeAt(0);
    }
  }

  /// Delivered rate over the recent window, in Hz.
  double get hz {
    if (_times.length < 2) return 0;
    final span = _times.last - _times.first;
    return span > 0 ? (_times.length - 1) * 1000 / span : 0;
  }

  double get lossFraction {
    final total = received + estimatedMissing;
    return total == 0 ? 0 : estimatedMissing / total;
  }

  void reset() {
    _times.clear();
    _lastMs = null;
    received = 0;
    estimatedMissing = 0;
    clockJumps = 0;
  }
}
