/// Persisted workout data: a [Session] of [SetRecord]s for one exercise.
///
/// Everything here is plain data with JSON round-tripping; storage lives in
/// `session_store.dart`. Analysis results are copied out of the analysis
/// engine's types so saved sessions don't depend on its internals.
library;

import '../analysis/exercises.dart';
import '../analysis/imu_quality.dart';
import '../analysis/set_analysis.dart';

enum WeightUnit {
  kg,
  lb;

  static WeightUnit fromName(String? name) =>
      values.firstWhere((u) => u.name == name, orElse: () => kg);
}

/// Sticking-region features for one rep, in percent of range of motion.
class StickingRecord {
  const StickingRecord({
    required this.startPct,
    required this.endPct,
    this.minVelocityPct,
    this.severeStartPct,
    this.severeEndPct,
  });

  factory StickingRecord.fromRegion(StickingRegion r) => StickingRecord(
        startPct: r.startPct,
        endPct: r.endPct,
        minVelocityPct: r.minVelocityPct,
        severeStartPct: r.severeStartPct,
        severeEndPct: r.severeEndPct,
      );

  factory StickingRecord.fromJson(Map<String, dynamic> j) => StickingRecord(
        startPct: _d(j['startPct'])!,
        endPct: _d(j['endPct'])!,
        minVelocityPct: _d(j['minVelocityPct']),
        severeStartPct: _d(j['severeStartPct']),
        severeEndPct: _d(j['severeEndPct']),
      );

  /// "Orange" band: velocity below 75 % of the early peak.
  final double startPct, endPct;

  /// The sticking point (slowest part of the rep).
  final double? minVelocityPct;

  /// "Red" band: velocity below 32.5 % of the early peak, if reached.
  final double? severeStartPct, severeEndPct;

  bool get hasSevere => severeStartPct != null && severeEndPct != null;

  Map<String, dynamic> toJson() => {
        'startPct': startPct,
        'endPct': endPct,
        if (minVelocityPct != null) 'minVelocityPct': minVelocityPct,
        if (severeStartPct != null) 'severeStartPct': severeStartPct,
        if (severeEndPct != null) 'severeEndPct': severeEndPct,
      };
}

/// One analysed rep, as stored.
class RepRecord {
  const RepRecord({
    required this.index,
    required this.startSec,
    required this.endSec,
    required this.meanVelocity,
    required this.peakVelocity,
    this.romMeters,
    this.sticking,
  });

  factory RepRecord.fromResult(RepResult r) => RepRecord(
        index: r.index,
        startSec: r.startSec,
        endSec: r.endSec,
        meanVelocity: r.meanVelocity,
        peakVelocity: r.peakVelocity,
        romMeters: r.romMeters,
        sticking:
            r.sticking == null ? null : StickingRecord.fromRegion(r.sticking!),
      );

  factory RepRecord.fromJson(Map<String, dynamic> j) => RepRecord(
        index: j['index'] as int,
        startSec: _d(j['startSec'])!,
        endSec: _d(j['endSec'])!,
        meanVelocity: _d(j['meanVelocity'])!,
        peakVelocity: _d(j['peakVelocity'])!,
        romMeters: _d(j['romMeters']),
        sticking: j['sticking'] == null
            ? null
            : StickingRecord.fromJson(j['sticking'] as Map<String, dynamic>),
      );

  /// 1-based rep number.
  final int index;

  /// Concentric phase, seconds from the start of the recording.
  final double startSec, endSec;

  /// m/s over the concentric phase.
  final double meanVelocity, peakVelocity;

  final double? romMeters;
  final StickingRecord? sticking;

  Map<String, dynamic> toJson() => {
        'index': index,
        'startSec': startSec,
        'endSec': endSec,
        'meanVelocity': meanVelocity,
        'peakVelocity': peakVelocity,
        if (romMeters != null) 'romMeters': romMeters,
        if (sticking != null) 'sticking': sticking!.toJson(),
      };
}

/// One recorded set. Analysis fields are empty/null when analysis failed;
/// [analysisError] then says why, and the raw CSV is still referenced.
class SetRecord {
  const SetRecord({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.weight,
    required this.unit,
    this.setType,
    this.rpe,
    this.note,
    this.reps = const [],
    this.pipeline,
    this.warnings = const [],
    this.measuredHz,
    this.rawCsvFile,
    this.sampleCount,
    this.analysisError,
    this.velocityTrace = const [],
    this.traceHz,
    this.videoFile,
    this.videoOffsetSec,
    this.imuQuality,
  });

  factory SetRecord.fromJson(Map<String, dynamic> j) => SetRecord(
        id: j['id'] as String,
        startedAt: _date(j['startedAt'])!,
        endedAt: _date(j['endedAt'])!,
        weight: _d(j['weight']) ?? 0,
        unit: WeightUnit.fromName(j['unit'] as String?),
        setType: _setType(j['setType'] as String?),
        rpe: _d(j['rpe']),
        note: j['note'] as String?,
        reps: [
          for (final r in (j['reps'] as List? ?? const []))
            RepRecord.fromJson(r as Map<String, dynamic>),
        ],
        pipeline: _pipeline(j['pipeline'] as String?),
        warnings: [
          for (final w in (j['warnings'] as List? ?? const [])) w as String,
        ],
        measuredHz: _d(j['measuredHz']),
        rawCsvFile: j['rawCsvFile'] as String?,
        sampleCount: j['sampleCount'] as int?,
        analysisError: j['analysisError'] as String?,
        velocityTrace: [
          for (final v in (j['velocityTrace'] as List? ?? const []))
            (v as num).toDouble(),
        ],
        traceHz: _d(j['traceHz']),
        videoFile: j['videoFile'] as String?,
        videoOffsetSec: _d(j['videoOffsetSec']),
        imuQuality: j['imuQuality'] == null
            ? null
            : ImuQualityMetrics.fromJson(j['imuQuality'] as Map<String, dynamic>),
      );

  final String id;
  final DateTime startedAt, endedAt;
  final double weight;
  final WeightUnit unit;
  final SetType? setType;

  /// Rate of perceived exertion, 5.0–10.0 in 0.5 steps.
  final double? rpe;
  final String? note;

  final List<RepRecord> reps;
  final PipelineKind? pipeline;
  final List<String> warnings;
  final double? measuredHz;

  /// Raw samples CSV, relative to the app documents directory
  /// (see `RecordingStore.relativePath`).
  final String? rawCsvFile;
  final int? sampleCount;
  final String? analysisError;

  /// Vertical velocity (m/s) at [traceHz], same time base as rep times.
  /// Downsampled from the analysis trace to keep session files small.
  final List<double> velocityTrace;
  final double? traceHz;

  /// Video of the set, relative to the app documents directory.
  final String? videoFile;

  /// Video time of sensor t = 0: `videoTime = repTime + videoOffsetSec`.
  final double? videoOffsetSec;

  /// Recording-quality metrics computed when the set was saved (Stance's
  /// `ImuQualityMetrics`); null for older sets or no sensor clock.
  final ImuQualityMetrics? imuQuality;

  bool get hasVideo => videoFile != null;

  /// [clearRpe] removes the RPE (a null [rpe] keeps the current one);
  /// likewise [clearSetType] and [clearNote].
  SetRecord copyWith({
    double? weight,
    WeightUnit? unit,
    SetType? setType,
    bool clearSetType = false,
    double? rpe,
    bool clearRpe = false,
    String? note,
    bool clearNote = false,
    List<RepRecord>? reps,
    double? videoOffsetSec,
    String? videoFile,
  }) =>
      SetRecord(
        id: id,
        startedAt: startedAt,
        endedAt: endedAt,
        weight: weight ?? this.weight,
        unit: unit ?? this.unit,
        setType: clearSetType ? null : setType ?? this.setType,
        rpe: clearRpe ? null : rpe ?? this.rpe,
        note: clearNote ? null : note ?? this.note,
        reps: reps ?? this.reps,
        pipeline: pipeline,
        warnings: warnings,
        measuredHz: measuredHz,
        rawCsvFile: rawCsvFile,
        sampleCount: sampleCount,
        analysisError: analysisError,
        velocityTrace: velocityTrace,
        traceHz: traceHz,
        videoFile: videoFile ?? this.videoFile,
        videoOffsetSec: videoOffsetSec ?? this.videoOffsetSec,
        imuQuality: imuQuality,
      );

  /// This set with a new analysis result (reprocessing): reps, pipeline,
  /// warnings, rate and trace replaced, the error cleared. Everything the
  /// lifter entered is kept.
  SetRecord withAnalysis({
    required List<RepRecord> reps,
    required PipelineKind pipeline,
    required List<String> warnings,
    required double measuredHz,
    required List<double> velocityTrace,
    required double? traceHz,
    double? videoOffsetSec,
  }) =>
      SetRecord(
        id: id,
        startedAt: startedAt,
        endedAt: endedAt,
        weight: weight,
        unit: unit,
        setType: setType,
        rpe: rpe,
        note: note,
        reps: reps,
        pipeline: pipeline,
        warnings: warnings,
        measuredHz: measuredHz,
        rawCsvFile: rawCsvFile,
        sampleCount: sampleCount,
        velocityTrace: velocityTrace,
        traceHz: traceHz,
        videoFile: videoFile,
        videoOffsetSec: videoOffsetSec ?? this.videoOffsetSec,
        imuQuality: imuQuality,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt.toUtc().toIso8601String(),
        'weight': weight,
        'unit': unit.name,
        if (setType != null) 'setType': setType!.key,
        if (rpe != null) 'rpe': rpe,
        if (note != null) 'note': note,
        'reps': [for (final r in reps) r.toJson()],
        if (pipeline != null) 'pipeline': pipeline!.name,
        'warnings': warnings,
        if (measuredHz != null) 'measuredHz': measuredHz,
        if (rawCsvFile != null) 'rawCsvFile': rawCsvFile,
        if (sampleCount != null) 'sampleCount': sampleCount,
        if (analysisError != null) 'analysisError': analysisError,
        if (velocityTrace.isNotEmpty)
          'velocityTrace': [
            for (final v in velocityTrace)
              v.isFinite ? double.parse(v.toStringAsFixed(4)) : 0,
          ],
        if (traceHz != null) 'traceHz': traceHz,
        if (videoFile != null) 'videoFile': videoFile,
        if (videoOffsetSec != null) 'videoOffsetSec': videoOffsetSec,
        if (imuQuality != null) 'imuQuality': imuQuality!.toJson(),
      };
}

/// Downsample a velocity trace to roughly [targetHz] for storage.
(List<double>, double) downsampleTrace(List<double> v, double hz,
    {double targetHz = 50}) {
  if (v.isEmpty || hz <= 0) return (const [], hz);
  final step = (hz / targetHz).round().clamp(1, 1 << 30);
  return ([for (var i = 0; i < v.length; i += step) v[i]], hz / step);
}

/// A training session: consecutive sets of one exercise.
class Session {
  const Session({
    required this.id,
    required this.exerciseId,
    required this.startedAt,
    this.endedAt,
    this.sets = const [],
    this.tags = const [],
  });

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        exerciseId: j['exerciseId'] as String,
        startedAt: _date(j['startedAt'])!,
        endedAt: _date(j['endedAt']),
        sets: [
          for (final s in (j['sets'] as List? ?? const []))
            SetRecord.fromJson(s as Map<String, dynamic>),
        ],
        tags: [for (final t in (j['tags'] as List? ?? const [])) t as String],
      );

  static const schemaVersion = 1;

  final String id;
  final String exerciseId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<SetRecord> sets;

  /// Stance-style session tags, e.g. `Day:Primary` (see session_tags.dart).
  final List<String> tags;

  /// The catalogue entry, or null if the id is no longer known.
  Exercise? get exercise {
    for (final e in Exercise.all) {
      if (e.id == exerciseId) return e;
    }
    return null;
  }

  String get exerciseTitle => exercise?.rawValue ?? exerciseId;

  int get totalReps => sets.fold(0, (n, s) => n + s.reps.length);

  /// Replace the set with the same id.
  Session replaceSet(SetRecord set) => copyWith(
        sets: [for (final s in sets) s.id == set.id ? set : s],
      );

  Session copyWith({DateTime? endedAt, List<SetRecord>? sets, List<String>? tags}) =>
      Session(
        id: id,
        exerciseId: exerciseId,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        sets: sets ?? this.sets,
        tags: tags ?? this.tags,
      );

  Map<String, dynamic> toJson() => {
        'version': schemaVersion,
        'id': id,
        'exerciseId': exerciseId,
        'startedAt': startedAt.toUtc().toIso8601String(),
        if (endedAt != null) 'endedAt': endedAt!.toUtc().toIso8601String(),
        'sets': [for (final s in sets) s.toJson()],
        if (tags.isNotEmpty) 'tags': tags,
      };
}

double? _d(Object? v) => (v as num?)?.toDouble();

DateTime? _date(Object? v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

SetType? _setType(String? key) {
  for (final t in SetType.values) {
    if (t.key == key) return t;
  }
  return null;
}

PipelineKind? _pipeline(String? name) {
  for (final p in PipelineKind.values) {
    if (p.name == name) return p;
  }
  return null;
}
