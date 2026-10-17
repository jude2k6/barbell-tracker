import 'dart:math' as math;

import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/analysis/set_analysis.dart';
import 'package:barbell_app/sensor/sensor_sample.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic set: bar position made of cosine ramps, sampled at [hz], with
/// the sensor tilted by a fixed quaternion and Gaussian accel noise.
List<SensorSample> syntheticSet({
  int reps = 3,
  double rom = 0.5,
  double descentSec = 1.2,
  double ascentSec = 0.8,
  double pauseSec = 0.2,
  double restSec = 0.5,
  double hz = 200,
  double noiseG = 0.003,
  int seed = 1,
}) {
  // Piecewise position: (duration, from, to).
  final segs = <(double, double, double)>[(2.0, 0, 0)];
  for (var r = 0; r < reps; r++) {
    segs
      ..add((descentSec, 0, -rom))
      ..add((pauseSec, -rom, -rom))
      ..add((ascentSec, -rom, 0))
      ..add((restSec, 0, 0));
  }
  segs.add((2.0, 0, 0));

  final rnd = math.Random(seed);
  double gauss() {
    final u = 1 - rnd.nextDouble(), v = rnd.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  // Sensor rotated 20° about X: gravity appears on both Y and Z.
  const ang = 20 * math.pi / 180;
  final qw = math.cos(ang / 2), qx = math.sin(ang / 2);

  final out = <SensorSample>[];
  final dt = 1 / hz;
  var t0 = 0.0;
  var i = 0;
  const startMs = 1760000000000;
  for (final (dur, from, to) in segs) {
    final n = (dur * hz).round();
    for (var k = 0; k < n; k++, i++) {
      final tau = k * dt;
      // a = d²x/dt² of x = from + (to-from) (1 - cos(pi tau/dur)) / 2
      final accel = from == to
          ? 0.0
          : (to - from) / 2 * math.pow(math.pi / dur, 2) * math.cos(math.pi * tau / dur);
      final worldZ = 1 + accel / 9.81;
      // Body-frame accel = R^T * world (world = [0,0,worldZ]).
      final ay = 2 * qw * qx * worldZ; // R row2 col1 = 2(yz+wx)
      final az = (1 - 2 * qx * qx) * worldZ;
      out.add(SensorSample(
        hostTimeUs: (startMs + (t0 + tau) * 1000) .round() * 1000,
        sensorTimeMs: (startMs + i * 1000 / hz).round(),
        ax: noiseG * gauss(),
        ay: ay + noiseG * gauss(),
        az: az + noiseG * gauss(),
        gx: 0, gy: 0, gz: 0,
        q0: qw, q1: qx, q2: 0, q3: 0,
      ));
    }
    t0 += dur;
  }
  return out;
}

void main() {
  test('squat: finds every rep with plausible velocity and ROM', () async {
    final result = await analyzeSet(syntheticSet(), Exercise.byId('squat_low_bar'));
    for (final r in result.reps) {
      // ignore: avoid_print
      print('rep ${r.index}: ${r.startSec.toStringAsFixed(2)}–${r.endSec.toStringAsFixed(2)} s '
          'mean ${r.meanVelocity.toStringAsFixed(3)} peak ${r.peakVelocity.toStringAsFixed(3)} '
          'rom ${r.romMeters?.toStringAsFixed(3)} sticking ${r.sticking?.startPct}-${r.sticking?.endPct}');
    }
    expect(result.reps, hasLength(3));
    expect(result.measuredHz, closeTo(200, 1));
    for (final r in result.reps) {
      expect(r.peakVelocity, closeTo(math.pi * 0.5 / (2 * 0.8), 0.12));
      expect(r.meanVelocity, inInclusiveRange(0.45, 0.75));
      expect(r.romMeters, isNotNull);
      expect(r.romMeters!, closeTo(0.5, 0.1));
      // Drift residual from the 5 s moving average widens the window a bit.
      expect(r.endSec - r.startSec, inInclusiveRange(0.7, 1.3));
    }
    // First concentric phase starts ~3.4 s.
    expect(result.reps.first.startSec, closeTo(2 + 1.2 + 0.2, 0.25));
  });

  test('known limitation: long standing pauses stretch reps (matches native)', () async {
    // The 5 s moving-average drift removal leaves positive residual velocity
    // after a rep when the next descent falls inside the window, so the
    // phase only closes when that descent starts.
    final result = await analyzeSet(
        syntheticSet(restSec: 1.5), Exercise.byId('squat_low_bar'));
    expect(result.reps, hasLength(3));
    expect(result.reps.first.endSec - result.reps.first.startSec, greaterThan(1.2));
    expect(result.reps.last.endSec - result.reps.last.startSec, closeTo(0.8, 0.2));
  });

  test('a smooth cosine ascent has no sticking region', () async {
    final result = await analyzeSet(syntheticSet(), Exercise.byId('squat_high_bar'));
    expect(result.reps.where((r) => r.sticking != null), isEmpty);
  });

  test('deadlift uses the fallback constants and warns', () async {
    final result = await analyzeSet(
      syntheticSet(descentSec: 0.9, ascentSec: 1.0),
      Exercise.byId('deadlift_conventional'),
    );
    expect(result.pipeline, PipelineKind.deadliftFallback);
    expect(result.warnings, isNotEmpty);
    expect(result.reps, hasLength(3));
  });

  test('no movement gives no reps', () async {
    final result = await analyzeSet(
      syntheticSet(reps: 0), Exercise.byId('bench_competition'));
    expect(result.reps, isEmpty);
  });

  test('too-short recordings are rejected', () {
    expect(
      analyzeSet(syntheticSet().sublist(0, 10), Exercise.byId('bench_competition')),
      throwsA(isA<AnalysisException>()),
    );
  });
}
