import 'dart:math' as math;

import 'package:barbell_app/analysis/imu_quality.dart';
import 'package:barbell_app/sensor/sensor_sample.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:barbell_app/workout/signal_quality.dart';
import 'package:flutter_test/flutter_test.dart';

SensorSample _s(int i,
        {int? sensorMs,
        int? hostMs,
        double ax = 0,
        double ay = 0,
        double az = 1,
        double gx = 0,
        List<double> q = const [1, 0, 0, 0]}) =>
    SensorSample(
      hostTimeUs: (hostMs ?? i * 5) * 1000,
      sensorTimeMs: sensorMs ?? i * 5,
      ax: ax, ay: ay, az: az,
      gx: gx, gy: 0, gz: 0,
      q0: q[0], q1: q[1], q2: q[2], q3: q[3],
    );

/// [n] samples at 200 Hz on both clocks.
List<SensorSample> _still(int n, {double az = 1}) =>
    [for (var i = 0; i < n; i++) _s(i, az: az)];

void main() {
  group('computeImuQuality', () {
    test('needs two samples with a sensor clock', () {
      expect(computeImuQuality([_s(0)]), isNull);
      expect(
          computeImuQuality([
            const SensorSample(
                hostTimeUs: 0, sensorTimeMs: null, ax: 0, ay: 0, az: 1,
                gx: 0, gy: 0, gz: 0, q0: 1, q1: 0, q2: 0, q3: 0),
            _s(1),
          ]),
          isNull);
    });

    test('a clean still recording: one still period, no loss', () {
      final m = computeImuQuality(_still(600))!; // 3 s
      expect(m.imuDataLossPct, 0);
      expect(m.gyroSaturationDurationS, 0);
      expect(m.accelSaturationDurationS, 0);
      // The high-pass starts at α·1 g, so stillness begins once it decays.
      expect(m.stillPeriodCount, 1);
      expect(m.stillPeriodGlobalZ, closeTo(1, 1e-9));
      expect(m.stillPeriodGlobalX, closeTo(0, 1e-9));
      expect(m.stillPeriodStdGlobalZ, closeTo(0, 1e-9));
      expect(m.stillPeriodStdZPerPeriod, hasLength(1));
      expect(m.numberOfImpacts, 0);
    });

    test('gaps longer than 1.5 intervals count as lost time', () {
      // 200 Hz with one 105 ms hole in 1 s of data.
      final samples = [
        for (var i = 0; i < 100; i++) _s(i),
        for (var i = 120; i < 200; i++) _s(i),
      ];
      final m = computeImuQuality(samples)!;
      final span = 199 * 5 / 1000;
      expect(m.imuDataLossPct, closeTo(0.105 / span * 100, 1e-9));
    });

    test('saturation: samples beyond the limit divided by the rate', () {
      final samples = [
        for (var i = 0; i < 200; i++)
          _s(i, ax: i < 10 ? 16 : 0, gx: i >= 190 ? -2000 : 0),
      ];
      final m = computeImuQuality(samples)!;
      expect(m.accelSaturationDurationS, closeTo(10 / 200, 1e-9));
      expect(m.gyroSaturationDurationS, closeTo(10 / 200, 1e-9));
    });

    test('a sharp spike between still spans counts as one impact', () {
      final samples = [
        for (var i = 0; i < 600; i++)
          _s(i, az: i >= 300 && i < 303 ? 5 : 1),
      ];
      final m = computeImuQuality(samples)!;
      expect(m.numberOfImpacts, 1);
      expect(m.stillPeriodCount, 2);
    });

    test('still periods are rotated to the world frame', () {
      // Sensor rolled 90° about X: the 1 g reads on sensor Y.
      final h = math.sqrt(0.5);
      final samples = [
        for (var i = 0; i < 600; i++) _s(i, ay: -1, az: 0, q: [h, h, 0, 0]),
      ];
      final m = computeImuQuality(samples)!;
      expect(m.stillPeriodGlobalZ, closeTo(-1, 1e-9));
      expect(m.stillPeriodGlobalY, closeTo(0, 1e-9));
    });

    test('JSON round trip, also through SetRecord', () {
      final m = computeImuQuality(_still(600))!;
      final back = ImuQualityMetrics.fromJson(m.toJson());
      expect(back.toJson(), m.toJson());

      final t = DateTime.utc(2026, 10, 17);
      final set = SetRecord(
          id: 'a', startedAt: t, endedAt: t, weight: 100,
          unit: WeightUnit.kg, imuQuality: m);
      final again = SetRecord.fromJson(set.toJson());
      expect(again.imuQuality!.stillPeriodCount, 1);
      expect(again.copyWith(rpe: 8).imuQuality, isNotNull);
      expect(SetRecord.fromJson(
              SetRecord(id: 'b', startedAt: t, endedAt: t, weight: 1,
                      unit: WeightUnit.kg)
                  .toJson())
          .imuQuality, isNull);
    });
  });

  group('assessSignalQuality', () {
    List<SensorSample> atHost(List<int> ms) =>
        [for (final (i, t) in ms.indexed) _s(i, hostMs: t)];

    test('null below two samples', () {
      expect(assessSignalQuality(atHost([0])), isNull);
    });

    test('10 ms steps: Good, 100 pkt/s', () {
      final q = assessSignalQuality(atHost([for (var i = 0; i < 50; i++) i * 10]))!;
      expect(q.rating, SignalRating.good);
      expect(q.rateLabel, '100 pkt/s');
      expect(q.completenessPercent, 100);
      expect(q.gapCount, 0);
    });

    test('200 Hz clamps completeness at 100 %', () {
      final q = assessSignalQuality(atHost([for (var i = 0; i < 50; i++) i * 5]))!;
      expect(q.completenessPercent, 100);
      expect(q.rateLabel, '200 pkt/s');
      expect(q.rating, SignalRating.good);
    });

    test('one gap over 20 ms makes a complete window Fair', () {
      final ms = [for (var i = 0; i < 50; i++) i * 5, 245 + 25];
      final q = assessSignalQuality(atHost(ms))!;
      expect(q.gapCount, 1);
      expect(q.completenessPercent, 100);
      expect(q.rating, SignalRating.fair);
    });

    test('completeness bands: ≥ 80 Fair, below Poor', () {
      // 12 ms steps: 10/12 = 83 %.
      final fair = assessSignalQuality(atHost([for (var i = 0; i < 50; i++) i * 12]))!;
      expect(fair.completenessPercent, closeTo(83.33, 0.01));
      expect(fair.rating, SignalRating.fair);
      // 15 ms steps: 67 %.
      final poor = assessSignalQuality(atHost([for (var i = 0; i < 50; i++) i * 15]))!;
      expect(poor.rating, SignalRating.poor);
      expect(poor.rateLabel, '67 pkt/s');
    });

    test('same-time samples count as zero intervals', () {
      // Two frames per 10 ms notification.
      final ms = [for (var i = 0; i < 51; i++) (i ~/ 2) * 10];
      final q = assessSignalQuality(atHost(ms))!;
      expect(q.rateLabel, '200 pkt/s');
      expect(q.rating, SignalRating.good);
    });

    test('assessRecentSignal uses the last 200 samples', () {
      // A slow start that falls out of the window.
      final ms = [
        for (var i = 0; i < 50; i++) i * 30,
        for (var i = 0; i < 200; i++) 1500 + i * 10,
      ];
      expect(assessSignalQuality(atHost(ms))!.rating, isNot(SignalRating.good));
      expect(assessRecentSignal(atHost(ms))!.rating, SignalRating.good);
    });
  });
}
