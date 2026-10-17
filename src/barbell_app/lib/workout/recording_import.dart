/// Importing a recording file as a new set (Stance's Home "Import
/// recording", `HomeViewModel.onRecordingFilePicked` and
/// `ProcessImportedRecordingUseCase`, notes §24).
///
/// Stance (debug builds only) reads a `.dat` recording, whose metadata
/// carries the exercise and weight, writes its samples to
/// `recordings/<id>-imu.csv`, and completes it as a set in a new session,
/// exactly like a recorded one. Here the file is a raw CSV
/// (`recording_csv.dart`), which has no exercise or weight, so the lifter
/// gives those after picking the file.
library;

import '../analysis/exercises.dart';
import '../analysis/imu_quality.dart';
import '../analysis/set_analysis.dart';
import '../recording/recording.dart';
import '../recording/recording_csv.dart';
import 'analysis_runner.dart';
import 'file_log.dart';
import 'ids.dart';
import 'session.dart';
import 'session_store.dart';

/// Stance's `LastImportedExercise`: what Home shows after an import.
class LastImportedRecording {
  const LastImportedRecording({
    required this.exercise,
    required this.sessionId,
    required this.recordedAt,
    this.rawCsvFile,
  });

  final Exercise exercise;
  final String sessionId;
  final DateTime recordedAt;

  /// The saved copy, relative to the documents directory; null if saving
  /// it failed.
  final String? rawCsvFile;
}

/// Stance's `RecordingImportUiState`.
class RecordingImportState {
  const RecordingImportState({
    this.isLoading = false,
    this.errorMessage,
    this.lastImported,
  });

  final bool isLoading;
  final String? errorMessage;
  final LastImportedRecording? lastImported;

  /// A new pick: loading, error and last import cleared (Stance keeps the
  /// previous import only to restore it on failure).
  static const loading = RecordingImportState(isLoading: true);

  /// `clearImportError`.
  RecordingImportState clearError() =>
      RecordingImportState(lastImported: lastImported);

  /// `dismissLastImport`.
  RecordingImportState dismissLast() =>
      RecordingImportState(errorMessage: errorMessage);
}

/// Saves [parsed] as a set of [exercise] in a new session: a copy of the
/// CSV in [recordings], then analysis, as after recording. The set is saved
/// even when analysis fails (the feedback page then offers to reprocess).
/// No set type is given; it can be added with Edit Set.
Future<LastImportedRecording> importRecordingAsSet(
  ParsedRecording parsed, {
  required Exercise exercise,
  required double weight,
  required WeightUnit unit,
  required RecordingStore recordings,
  required SessionStore sessions,
  required SetAnalyzer analyze,
}) async {
  final setId = newId();
  final recording = parsed.toRecording();
  String? rawPath;
  try {
    rawPath = recordings.relativePath(await recordings.save(recording));
  } catch (e) {
    AppLog.e('RecordingRepository', 'Saving imported recording failed', e);
  }

  SetAnalysis? analysis;
  String? error;
  try {
    analysis = await analyze(parsed.samples, exercise);
  } catch (e) {
    error = describeAnalysisError(e);
    AppLog.e('SetCompletion', 'analysis failed set=$setId (import)', e);
  }
  final (trace, traceHz) = analysis == null
      ? (const <double>[], null)
      : downsampleTrace(analysis.velocity, analysis.velocityHz);
  final set = SetRecord(
    id: setId,
    startedAt: parsed.startedAt,
    endedAt: parsed.endedAt,
    weight: weight,
    unit: unit,
    reps: [
      for (final r in analysis?.reps ?? const <RepResult>[])
        RepRecord.fromResult(r),
    ],
    pipeline: analysis?.pipeline,
    warnings: analysis?.warnings ?? const [],
    measuredHz: analysis?.measuredHz,
    rawCsvFile: rawPath,
    sampleCount: parsed.samples.length,
    analysisError: error,
    velocityTrace: trace,
    traceHz: traceHz,
    imuQuality: computeImuQuality(parsed.samples),
  );
  final session = Session(
    id: newId(),
    exerciseId: exercise.id,
    startedAt: set.startedAt,
    endedAt: set.endedAt,
    sets: [set],
  );
  await sessions.save(session);
  AppLog.i('SetCompletion',
      'imported set=$setId session=${session.id} exercise=${exercise.rawValue} '
      'samples=${parsed.samples.length} reps=${set.reps.length}');
  return LastImportedRecording(
    exercise: exercise,
    sessionId: session.id,
    recordedAt: parsed.startedAt,
    rawCsvFile: rawPath,
  );
}
