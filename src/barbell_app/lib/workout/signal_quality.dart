import '../sensor/sensor_sample.dart';

/// Stance's `SignalQuality.Rating`; [label] is the badge text.
enum SignalRating {
  good('Good'),
  fair('Fair'),
  poor('Poor');

  const SignalRating(this.label);
  final String label;
}

/// Live connection quality while recording, Stance's `SignalQuality`
/// (notes §21). Uses the phone's receive times, not the sensor clock.
class SignalQuality {
  const SignalQuality({
    required this.packetsPerSecond,
    required this.gapCount,
    required this.completenessPercent,
    required this.rating,
  });

  final double packetsPerSecond;

  /// Receive intervals longer than twice the expected interval.
  final int gapCount;

  /// Samples received versus expected over the window, 0–100.
  final double completenessPercent;
  final SignalRating rating;

  /// Badge subtitle, Stance's `"%.0f pkt/s"`.
  String get rateLabel => '${packetsPerSecond.toStringAsFixed(0)} pkt/s';
}

/// Stance passes the last 200 samples on every update.
const signalQualityWindow = 200;

/// Stance's `DEFAULT_EXPECTED_INTERVAL_MS` (100 Hz). The sensor is set to
/// 200 Hz, so completeness only drops once delivery falls below 100 Hz.
const defaultExpectedIntervalMs = 10;

/// Stance's `AssessSignalQualityUseCase`: Good at ≥ 95 % complete with no
/// gap, Fair at ≥ 80 %, else Poor. Null for fewer than two samples.
SignalQuality? assessSignalQuality(List<SensorSample> window,
    {int expectedIntervalMs = defaultExpectedIntervalMs}) {
  if (window.length < 2) return null;
  final ms = [for (final s in window) s.hostTimeUs ~/ 1000];
  final intervals = [for (var i = 1; i < ms.length; i++) ms[i] - ms[i - 1]];
  final gaps = intervals.where((d) => d > 2 * expectedIntervalMs).length;
  final avg = intervals.fold(0, (s, d) => s + d) / intervals.length;
  final rate = avg > 0 ? 1000 / avg : 0.0;
  final span = ms.last - ms.first;
  var expected = 1.0;
  if (expectedIntervalMs > 0 && span > 0) {
    expected = span / expectedIntervalMs;
    if (expected < 1) expected = 1;
  }
  final complete =
      ((window.length - 1) / expected * 100).clamp(0, 100).toDouble();
  final rating = complete >= 95 && gaps == 0
      ? SignalRating.good
      : complete >= 80
          ? SignalRating.fair
          : SignalRating.poor;
  return SignalQuality(
    packetsPerSecond: rate,
    gapCount: gaps,
    completenessPercent: complete,
    rating: rating,
  );
}

/// The window Stance assesses: the last [signalQualityWindow] samples.
SignalQuality? assessRecentSignal(List<SensorSample> samples) =>
    assessSignalQuality(samples.length > signalQualityWindow
        ? samples.sublist(samples.length - signalQualityWindow)
        : samples);
