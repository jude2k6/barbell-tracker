import '../analysis/exercises.dart';
import 'file_log.dart';
import 'session.dart';

/// The block Stance logs when a set is completed
/// (`CompletedSetLogReporter.buildSetCompletedLines`, tag `SetCompleted`),
/// one log line per entry. Lines for data we do not have are left out, as
/// Stance leaves out null ones: account (Firebase uid, email), the
/// Stance-encoder ("transducer") counts, and the cloud preprocessing outcome
/// (we log the local pipeline in `preprocessing` instead).
List<String> setCompletedLines(
  SetRecord set, {
  required Exercise exercise,
  required String sessionId,
  String? sensorName,
  DateTime? loggedAt,
}) {
  final now = loggedAt ?? DateTime.now();
  String f4(double v) => v.toStringAsFixed(4);
  final q = set.imuQuality;
  final raw = set.rawCsvFile;
  return [
    '========== SET COMPLETED BEGIN ==========',
    'event=set_completed',
    'recordingId=${set.id}',
    'sessionGroupId=$sessionId',
    'exercise=${exercise.rawValue}',
    'weight=${set.weight}',
    'weightUnit=${set.unit.name}',
    'setType=${set.setType?.key ?? 'none'}',
    'source=sensor',
    'setStartUtc=${set.startedAt.toUtc().toIso8601String()}',
    'setEndUtc=${set.endedAt.toUtc().toIso8601String()}',
    'setStartLocal=${set.startedAt.toIso8601String()}',
    'setEndLocal=${set.endedAt.toIso8601String()}',
    'setDurationMs=${set.endedAt.difference(set.startedAt).inMilliseconds}',
    'deviceTimezone=${now.timeZoneName} (UTC${_offset(now.timeZoneOffset)})',
    'dataPointCount=${set.sampleCount ?? 0}',
    'meanFrequencyHz=${set.measuredHz == null ? 'unknown' : set.measuredHz!.toStringAsFixed(2)}',
    'preprocessing=${set.analysisError != null ? 'FAILED' : set.pipeline?.name ?? 'unknown'}',
    if (set.analysisError != null) 'preprocessingError=${set.analysisError}',
    'repCount=${set.reps.length}',
    'repMeanVelocitiesMps=[${set.reps.map((r) => f4(r.meanVelocity)).join(', ')}]',
    'witMotionDevice=${sensorName ?? 'unknown'}',
    'witMotionReadingCount=${set.sampleCount ?? 0}',
    if (q != null) ...[
      'imuDataLossPct=${f4(q.imuDataLossPct)}',
      'gyroSaturationDurationS=${f4(q.gyroSaturationDurationS)}',
      'accelSaturationDurationS=${f4(q.accelSaturationDurationS)}',
      'stillPeriodCount=${q.stillPeriodCount}',
      'numberOfImpacts=${q.numberOfImpacts}',
    ],
    'datFileWritten=${raw != null}',
    if (raw != null) 'datFileName=${raw.split('/').last}',
    'videoLocalIdentifier=${set.videoFile ?? 'N/A'}',
    'loggedAtUtc=${now.toUtc().toIso8601String()}',
    'loggedAtLocal=${now.toIso8601String()}',
    '========== SET COMPLETED END ==========',
  ];
}

/// Writes [setCompletedLines] to the log.
void logSetCompleted(
  SetRecord set, {
  required Exercise exercise,
  required String sessionId,
  String? sensorName,
}) {
  for (final line in setCompletedLines(set,
      exercise: exercise, sessionId: sessionId, sensorName: sensorName)) {
    AppLog.i('SetCompleted', line);
  }
}

String _offset(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.isNegative ? '-' : '+'}${two(d.inHours.abs())}:${two(d.inMinutes.abs() % 60)}';
}
