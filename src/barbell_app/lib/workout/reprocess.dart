/// Re-running analysis on a saved set (Stance's `ReprocessSetUseCase` and
/// the feedback page's `ReprocessBanner`, notes §24).
///
/// Stance offers it for a set whose analysis failed or found no reps
/// (`SessionFeedbackSetUi.needsReprocessing`), one set at a time, from the
/// banner on the feedback page's set sheet. It reads the recording from its
/// in-memory store, so it only works until the app restarts
/// ([ReprocessState.unavailable] after that). Here the source is the set's
/// raw CSV, so it works for any set whose CSV is still on the phone.
library;

import 'dart:io';

import '../analysis/exercises.dart';
import '../recording/recording.dart';
import '../recording/recording_csv.dart';
import 'analysis_runner.dart';
import 'file_log.dart';
import 'session.dart';

/// Stance's `ReprocessUiState`. The page keeps one, reset to [idle] when
/// another set is selected.
enum ReprocessState {
  idle,
  inProgress,
  failed,
  stillEmpty,
  unavailable;

  /// The banner's message (`feedback_reprocess_*`).
  String get message => switch (this) {
        unavailable => 'Reprocessing is available right after recording. '
            "This set's data is backed up and can be reprocessed by the team.",
        failed => "Reprocessing didn't work this time. You can try again.",
        stillEmpty =>
          "We still couldn't find reps in this set. Your data is backed up for review.",
        idle || inProgress =>
          "We couldn't finish processing this set. Your data is safe and already backed up.",
      };

  /// Whether the banner shows its button ("Reprocess", or the spinner
  /// "Reprocessing…" while [inProgress]); not after "unavailable" or
  /// "still empty".
  bool get showsButton => this == idle || this == inProgress || this == failed;
}

/// Stance's `needsReprocessing`: preprocessing failed or found no reps
/// (`VERCEL_FAILED`, `VERCEL_EMPTY`, `DEADLIFT_TCN_FAILED`,
/// `DEADLIFT_TCN_EMPTY`).
bool needsReprocessing(SetRecord set) =>
    set.analysisError != null || set.reps.isEmpty;

/// Stance's `ReprocessSetResult`.
sealed class ReprocessResult {
  const ReprocessResult();
}

/// Analysis ran; [set] is the updated set to save (even with no reps, as
/// Stance stores the empty result too).
class ReprocessSuccess extends ReprocessResult {
  const ReprocessSuccess(this.set);
  final SetRecord set;
  int get repCount => set.reps.length;
}

/// No raw recording to analyse.
class ReprocessUnavailable extends ReprocessResult {
  const ReprocessUnavailable();
}

class ReprocessFailed extends ReprocessResult {
  const ReprocessFailed(this.message);
  final String? message;
}

/// The page state after [result] (Stance's `reprocessSelectedSet`).
ReprocessState stateAfter(ReprocessResult result) => switch (result) {
      ReprocessSuccess(:final repCount) =>
        repCount > 0 ? ReprocessState.idle : ReprocessState.stillEmpty,
      ReprocessUnavailable() => ReprocessState.unavailable,
      ReprocessFailed() => ReprocessState.failed,
    };

/// Re-analyses [set] from its raw CSV. Never throws.
///
/// Only the analysis fields change ([SetRecord.withAnalysis]); weight, set
/// type, RPE, note, video and IMU quality stay, as Stance's
/// `updateSetAfterReprocess` only replaces reps, velocity and status. If
/// the set's analysis had failed, its video offset was measured from the
/// first sample, so it moves to the new analysis origin.
Future<ReprocessResult> reprocessSet(
  SetRecord set, {
  required Exercise exercise,
  required RecordingStore recordings,
  required SetAnalyzer analyze,
}) async {
  const tag = 'ReprocessSet';
  final raw = set.rawCsvFile;
  if (raw == null) return const ReprocessUnavailable();
  final String text;
  try {
    final file = await recordings.resolve(raw);
    if (!await file.exists()) return const ReprocessUnavailable();
    text = await file.readAsString();
  } on FileSystemException {
    return const ReprocessUnavailable();
  }

  try {
    final ParsedRecording parsed;
    try {
      parsed = parseRecordingCsv(text);
    } on RecordingCsvException catch (e) {
      // Stance's message for a recording without samples.
      if (e.message == 'CSV is empty' || e.message.startsWith('Need at least')) {
        return const ReprocessFailed('No IMU data recorded — re-record the set');
      }
      rethrow;
    }
    final samples = parsed.samples;
    final analysis = await analyze(samples, exercise);
    final (trace, traceHz) =
        downsampleTrace(analysis.velocity, analysis.velocityHz);
    final oldOffset = set.videoOffsetSec;
    final origin = analysis.originHostTimeUs;
    AppLog.i(tag,
        'reprocessed set=${set.id} pipeline=${analysis.pipeline.name} reps=${analysis.reps.length}');
    return ReprocessSuccess(set.withAnalysis(
      reps: [for (final r in analysis.reps) RepRecord.fromResult(r)],
      pipeline: analysis.pipeline,
      warnings: analysis.warnings,
      measuredHz: analysis.measuredHz,
      velocityTrace: trace,
      traceHz: traceHz,
      videoOffsetSec: set.analysisError != null && oldOffset != null && origin != null
          ? oldOffset + (origin - samples.first.hostTimeUs) / 1e6
          : null,
    ));
  } catch (e) {
    AppLog.e(tag, 'Reprocess failed for ${set.id}', e);
    return ReprocessFailed(describeAnalysisError(e));
  }
}
