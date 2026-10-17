import 'dart:math' as math;

import 'package:barbell_app/analysis/deadlift_pipeline.dart';
import 'package:barbell_app/analysis/motion_mapper.dart';
import 'package:barbell_app/analysis/set_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

import 'squat_bench_pipeline_test.dart' show syntheticSet;

/// Stand-ins for the TFLite models, which need native libraries that the
/// test host doesn't have.
class IdentityRunner implements ModelRunner {
  @override
  List<double> predict(List<double> input) => input;
}

/// "Lift probability" = sigmoid of de-normalised velocity above 0.03 m/s,
/// so a "lift" spans nearly the whole concentric phase like the real TCN.
class VelocityGateRunner implements ModelRunner {
  @override
  List<double> predict(List<double> input) => [
        for (final x in input)
          50 * (x * DeadliftTcnPipeline.tcnStd + DeadliftTcnPipeline.tcnMean - 0.03),
      ];
}

void main() {
  final pipeline = DeadliftTcnPipeline(
    DeadliftModelsRunners(unet: IdentityRunner(), tcn: VelocityGateRunner()),
  );

  test('segments three pulls with silver mean/peak velocity', () {
    final samples = syntheticSet(
      rom: -0.5, // negative ROM: the first ramp of each rep goes up
      descentSec: 1.0,
      ascentSec: 0.6,
      pauseSec: 0.5,
      restSec: 1.5,
    );
    final motion = MotionMapper.map(samples);
    final result = pipeline.process(motion);
    final analysis = deadliftResultToAnalysis(motion, result);
    for (final r in analysis.reps) {
      // ignore: avoid_print
      print('pull ${r.index}: ${r.startSec.toStringAsFixed(2)}–${r.endSec.toStringAsFixed(2)} s '
          'mean ${r.meanVelocity.toStringAsFixed(3)} peak ${r.peakVelocity.toStringAsFixed(3)}');
    }
    expect(analysis.pipeline, PipelineKind.deadliftTcn);
    expect(analysis.reps, hasLength(3));
    for (final r in analysis.reps) {
      // Cosine 0.5 m in 1.0 s: peak π/4 ≈ 0.785 m/s, mean 0.5 m/s.
      expect(r.peakVelocity, closeTo(math.pi / 4, 0.12));
      expect(r.meanVelocity, closeTo(0.5, 0.12));
      expect(r.romMeters, isNull);
    }
    expect(analysis.reps.first.startSec, closeTo(2.0, 0.3));
    expect(analysis.warnings, isEmpty);
  });

  test('U-Net windows overlap-average back to the input length', () {
    final raw = [for (var i = 0; i < 2345; i++) math.sin(i / 50)];
    final out = pipeline.runUnet(raw);
    expect(out, hasLength(raw.length));
    for (var i = 0; i < raw.length; i++) {
      expect(out[i], closeTo(raw[i], 1e-12));
    }
  });

  test('signal helpers match their scipy counterparts on simple cases', () {
    expect(DeadliftTcnPipeline.reflectPadRight([1, 2, 3], 3), [1, 2, 3, 2, 1, 2]);
    expect(DeadliftTcnPipeline.uniformFilter1d([1, 2, 3], 3), [
      closeTo(4 / 3, 1e-12), closeTo(2, 1e-12), closeTo(8 / 3, 1e-12),
    ]);
    expect(DeadliftTcnPipeline.gradient([0, 1, 4, 9]), [1, 2, 4, 5]);
    expect(DeadliftTcnPipeline.findPeaks([0, 2, 1, 3, 0], 1.5), [1, 3]);
    expect(DeadliftTcnPipeline.prominence(1, [0, 2, 1, 3, 0]), 1);
    expect(DeadliftTcnPipeline.findProminentPeaks([0, 2, 0, 0, 3, 0], 3, 0), [1, 4]);
    expect(DeadliftTcnPipeline.findProminentPeaks([0, 2, 0, 3, 0], 3, 0), [3]);
  });
}
