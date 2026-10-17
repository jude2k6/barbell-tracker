/// Public contract between the analysis engine and the rest of the app.
///
/// The UI depends only on this file. Pipelines live alongside it in
/// `lib/analysis/` and may change freely behind [analyzeSet].
library;

import '../sensor/sensor_sample.dart';
import 'exercises.dart';
import 'deadlift_models.dart';
import 'deadlift_pipeline.dart';
import 'motion_mapper.dart';
import 'squat_bench_pipeline.dart';

export 'deadlift_models.dart' show DeadliftModels;
export 'squat_bench_pipeline.dart' show PipelineOptions;

/// Sticking-region features for one rep, in percent of the rep's range of
/// motion (1–100). Null when the rep had no detectable sticking region.
class StickingRegion {
  const StickingRegion({
    required this.startPct,
    required this.endPct,
    this.minVelocityPct,
    this.severeStartPct,
    this.severeEndPct,
  });

  /// Velocity first drops below 75 % of its early peak ("orange" band).
  final double startPct;

  /// Velocity regains 75 % (or a second dip starts).
  final double endPct;

  /// Slowest point of the profile (the sticking point).
  final double? minVelocityPct;

  /// Band below 32.5 % of the early peak ("red" band), if reached.
  final double? severeStartPct;
  final double? severeEndPct;

  double get widthPct => endPct - startPct;
}

class RepResult {
  const RepResult({
    required this.index,
    required this.startSec,
    required this.endSec,
    required this.meanVelocity,
    required this.peakVelocity,
    required this.romMeters,
    this.sticking,
  });

  /// 1-based rep number.
  final int index;

  /// Concentric phase, seconds from the start of the recording.
  final double startSec, endSec;

  /// m/s over the concentric phase.
  final double meanVelocity, peakVelocity;

  /// Range of motion in metres, or null if it could not be computed.
  final double? romMeters;

  final StickingRegion? sticking;
}

enum PipelineKind { squatBenchNative, deadliftTcn, deadliftFallback }

class SetAnalysis {
  const SetAnalysis({
    required this.reps,
    required this.velocity,
    required this.velocityHz,
    required this.measuredHz,
    required this.pipeline,
    this.originHostTimeUs,
    this.warnings = const [],
  });

  final List<RepResult> reps;

  /// Vertical bar velocity trace for the whole recording, m/s, uniformly
  /// sampled at [velocityHz].
  final List<double> velocity;
  final double velocityHz;

  /// Mean sample rate measured from the sensor timestamps.
  final double measuredHz;

  final PipelineKind pipeline;

  /// Phone clock (µs since epoch) of t = 0 for [velocity] and the rep
  /// times: the first valid sample's host timestamp. Used to line the set
  /// up with a video recorded on the same phone.
  final int? originHostTimeUs;

  /// Human-readable notes (e.g. "low sample rate", "fallback used").
  final List<String> warnings;

  double? get bestMeanVelocity => reps.isEmpty
      ? null
      : reps.map((r) => r.meanVelocity).reduce((a, b) => a > b ? a : b);
}

class AnalysisException implements Exception {
  AnalysisException(this.message);
  final String message;
  @override
  String toString() => 'AnalysisException: $message';
}

/// Analyse one recorded set. Runs off the UI isolate in callers' hands
/// (wrap with `compute` / `Isolate.run`). Throws [AnalysisException] when
/// the recording is unusable (too short, no valid samples).
Future<SetAnalysis> analyzeSet(
  List<SensorSample> samples,
  Exercise exercise, {
  PipelineOptions options = const PipelineOptions(),
  DeadliftModels? deadliftModels,
}) async {
  if (samples.length < 50) {
    throw AnalysisException('Recording too short (${samples.length} samples)');
  }
  final MappedMotion motion;
  try {
    motion = MotionMapper.map(samples);
  } on ArgumentError catch (e) {
    throw AnalysisException('${e.message}');
  }

  final warnings = <String>[];
  if (exercise.isDeadlift) {
    // Reference app (§10): TCN first; native threshold pipeline only if it
    // throws. An empty TCN result is kept as is.
    if (deadliftModels != null) {
      try {
        return _runDeadliftTcn(motion, deadliftModels);
      } catch (e) {
        warnings.add('Deadlift model failed ($e); used the threshold fallback.');
      }
    } else {
      warnings.add('Deadlift models not loaded; used the threshold fallback.');
    }
  }
  final pipeline = exercise.isDeadlift
      ? PipelineKind.deadliftFallback
      : PipelineKind.squatBenchNative;

  final s = motion.samples;
  final Preprocessed pre;
  try {
    pre = preprocess(
      ax: [for (final x in s) x.ax],
      ay: [for (final x in s) x.ay],
      az: [for (final x in s) x.az],
      q0: [for (final x in s) x.q0],
      q1: [for (final x in s) x.q1],
      q2: [for (final x in s) x.q2],
      q3: [for (final x in s) x.q3],
      timestampsMs: [for (final t in motion.timeSec) (t * 1000).roundToDouble()],
      options: options,
    );
  } on ArgumentError catch (e) {
    throw AnalysisException('${e.message}');
  }
  if (pre.fs < 150) {
    warnings.add('Sample rate ${pre.fs.toStringAsFixed(0)} Hz is below the 200 Hz '
        'the thresholds were tuned for.');
  }

  final native = postprocess(
    v: pre.vertical,
    fs: pre.fs,
    totalSec: motion.timeSec.last,
    exerciseRaw: exercise.rawValue,
  );

  final reps = [
    for (var i = 0; i < native.length; i++)
      RepResult(
        index: i + 1,
        startSec: native[i].startSec,
        endSec: native[i].endSec,
        meanVelocity: native[i].meanVelocity,
        peakVelocity: native[i].peakVelocity,
        romMeters: native[i].rom,
        sticking: _sticking(native[i].profile),
      ),
  ];
  return SetAnalysis(
    reps: reps,
    velocity: pre.vertical,
    velocityHz: pre.fs,
    measuredHz: pre.fs,
    pipeline: pipeline,
    originHostTimeUs: motion.samples.first.hostTimeUs,
    warnings: warnings,
  );
}

SetAnalysis _runDeadliftTcn(MappedMotion motion, DeadliftModels models) {
  final runners = models.createRunners();
  try {
    return deadliftResultToAnalysis(motion, DeadliftTcnPipeline(runners).process(motion));
  } finally {
    (runners.unet as TfliteRunner).close();
    (runners.tcn as TfliteRunner).close();
  }
}

/// Shapes a [DeadliftResult] like the reference app's
/// `ProcessDeadliftRecordingUseCase` (no ROM, no sticking features).
SetAnalysis deadliftResultToAnalysis(MappedMotion motion, DeadliftResult r) {
  final dt = motion.timeSec.length > 1
      ? (motion.timeSec.last - motion.timeSec.first) / (motion.timeSec.length - 1)
      : DeadliftTcnPipeline.dt;
  return SetAnalysis(
    reps: [
      for (var i = 0; i < r.reps.length; i++)
        RepResult(
          index: i + 1,
          startSec: r.reps[i].startSec,
          endSec: r.reps[i].endSec,
          meanVelocity: r.reps[i].meanVelocity,
          peakVelocity: r.reps[i].peakVelocity,
          romMeters: null,
        ),
    ],
    velocity: r.correctedVelocity,
    velocityHz: DeadliftTcnPipeline.sampleRate,
    measuredHz: dt > 0 ? 1 / dt : 0,
    pipeline: PipelineKind.deadliftTcn,
    originHostTimeUs: motion.samples.first.hostTimeUs,
    warnings: [
      if (dt > 0 && (1 / dt - DeadliftTcnPipeline.sampleRate).abs() > 20)
        'Sample rate ${(1 / dt).toStringAsFixed(0)} Hz: the deadlift model assumes '
            '200 Hz, so velocities are scaled by ${(DeadliftTcnPipeline.dt / dt).toStringAsFixed(2)}.',
    ],
  );
}

StickingRegion? _sticking(ProfileFeatures p) {
  if (p.stickStart == 0 || p.stickEnd == 0) return null;
  double? nz(num x) => x == 0 ? null : x.toDouble();
  return StickingRegion(
    startPct: p.stickStart.toDouble(),
    endPct: p.stickEnd.toDouble(),
    minVelocityPct: nz(p.vMinPos),
    severeStartPct: nz(p.lowStart),
    severeEndPct: nz(p.lowEnd),
  );
}
