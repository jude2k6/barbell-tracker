import 'dart:io';

import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/analysis/set_analysis.dart';
import 'package:barbell_app/recording/recording.dart';
import 'package:barbell_app/recording/recording_csv.dart';
import 'package:barbell_app/sensor/sensor_sample.dart';
import 'package:barbell_app/workout/recording_import.dart';
import 'package:barbell_app/workout/reprocess.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:barbell_app/workout/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime.utc(2026, 10, 12, 9);

SensorSample _sample(int i, {bool sensorClock = true}) => SensorSample(
      hostTimeUs: _start.microsecondsSinceEpoch + i * 5000,
      sensorTimeMs: sensorClock ? _start.millisecondsSinceEpoch + i * 5 : null,
      ax: 0.01 * i, ay: 0, az: 1,
      gx: 0.5, gy: -0.25, gz: 0,
      q0: 1, q1: 0, q2: 0, q3: 0,
    );

Recording _recording(int n, {bool sensorClock = true}) =>
    Recording(sensorName: 'WT901 BLE68', startedAt: _start)
      ..samples.addAll([for (var i = 0; i < n; i++) _sample(i, sensorClock: sensorClock)]);

String _msg(void Function() f) {
  try {
    f();
  } on RecordingCsvException catch (e) {
    return e.message;
  }
  fail('no RecordingCsvException');
}

RepResult _rep(int i) => RepResult(
      index: i,
      startSec: i.toDouble(),
      endSec: i + 0.8,
      meanVelocity: 0.5,
      peakVelocity: 0.9,
      romMeters: 0.5,
    );

SetAnalysis _analysis(int reps, {int? origin}) => SetAnalysis(
      reps: [for (var i = 1; i <= reps; i++) _rep(i)],
      velocity: List.filled(400, 0.1),
      velocityHz: 200,
      measuredHz: 199.5,
      pipeline: PipelineKind.squatBenchNative,
      originHostTimeUs: origin,
    );

void main() {
  group('parseRecordingCsv', () {
    test('reads back our own CSV, comment included', () {
      final r = parseRecordingCsv(_recording(3).toCsv());
      expect(r.samples, hasLength(3));
      expect(r.sensorName, 'WT901 BLE68');
      expect(r.startedAt, _start.toLocal());
      final s = r.samples[2];
      expect(s.hostTimeUs, _sample(2).hostTimeUs);
      expect(s.sensorTimeMs, _sample(2).sensorTimeMs);
      expect(s.ax, closeTo(0.02, 1e-12));
      expect(s.gy, -0.25);
      expect(s.q0, 1);
      expect(r.endedAt.microsecondsSinceEpoch, s.hostTimeUs);
    });

    test('an empty sensor clock reads as null', () {
      final r = parseRecordingCsv(_recording(2, sensorClock: false).toCsv());
      expect(r.samples.first.sensorTimeMs, isNull);
    });

    test("reads Stance's IMU export: chip time, gyro, accel, quaternion", () {
      const csv = '﻿$stanceImuCsvHeader\n'
          '2026-10-12T09:00:00.000,1,2,3,0.1,0.2,0.9,1,0,0,0\n'
          '\n'
          '2026-10-12 09:00:00.005,1,2,3,0.1,0.2,0.9,0.5,0.5,0.5,0.5\n';
      final r = parseRecordingCsv(csv);
      expect(r.samples, hasLength(2));
      final a = r.samples.first;
      expect(a.sensorTimeMs, _start.millisecondsSinceEpoch);
      expect(a.hostTimeUs, _start.microsecondsSinceEpoch);
      expect([a.gx, a.gy, a.gz, a.ax, a.ay, a.az], [1, 2, 3, 0.1, 0.2, 0.9]);
      expect(r.samples[1].sensorTimeMs, _start.millisecondsSinceEpoch + 5);
      expect(r.samples[1].q3, 0.5);
      expect(r.sensorName, isNull);
      expect(r.startedAt.isAtSameMomentAs(_start), isTrue);
    });

    test("Stance's error messages", () {
      expect(_msg(() => parseRecordingCsv('')), 'CSV is empty');
      expect(_msg(() => parseRecordingCsv('# sensor=x started=y\n')), 'CSV is empty');
      expect(_msg(() => parseRecordingCsv('a,b,c\n1,2,3\n')),
          'Unexpected CSV header. Expected exact export header line.');
      expect(
          _msg(() => parseRecordingCsv('$stanceImuCsvHeader\n'
              '2026-10-12T09:00:00.000,1,2,3\n')),
          'Line 2: expected 11 columns, got 4');
      expect(
          _msg(() => parseRecordingCsv('$stanceImuCsvHeader\n'
              '2026-10-12T09:00:00.000,1,2,3,x,0,0,1,0,0,0\n')),
          'Line 2: invalid Acc X value "x"');
      expect(
          _msg(() => parseRecordingCsv('$stanceImuCsvHeader\n'
              '2026-10-12T09:00:00.000,1,2,3,0,0,0,1,0,0,0\n')),
          'Need at least 2 data rows, got 1');
      expect(
          _msg(() => parseRecordingCsv('$stanceImuCsvHeader\n'
              'noon,1,2,3,0,0,0,1,0,0,0\nnoon,1,2,3,0,0,0,1,0,0,0\n')),
          'Line 2: invalid Timestamp value "noon"');
      // Our format: physical line numbers, after the comment line.
      final ours = _recording(2).toCsv().replaceFirst(',0.5,', ',half,');
      expect(_msg(() => parseRecordingCsv(ours)), 'Line 3: invalid gx_dps value "half"');
      expect(_msg(() => parseRecordingCsv('${Recording.csvHeader}\n1,2,3\n')),
          'Line 2: expected 12 columns, got 3');
    });
  });

  group('reprocess state', () {
    final base = SetRecord(
      id: 's',
      startedAt: _start,
      endedAt: _start,
      weight: 100,
      unit: WeightUnit.kg,
      reps: const [
        RepRecord(index: 1, startSec: 0, endSec: 1, meanVelocity: 0.5, peakVelocity: 0.8),
      ],
    );

    test('needed when analysis failed or found no reps', () {
      expect(needsReprocessing(base), isFalse);
      expect(needsReprocessing(base.copyWith(reps: const [])), isTrue);
      expect(
          needsReprocessing(SetRecord(
              id: 'f', startedAt: _start, endedAt: _start, weight: 0,
              unit: WeightUnit.kg, analysisError: 'boom')),
          isTrue);
    });

    test("result → state and banner, as Stance's reprocessSelectedSet", () {
      expect(stateAfter(ReprocessSuccess(base)), ReprocessState.idle);
      expect(stateAfter(ReprocessSuccess(base.copyWith(reps: const []))),
          ReprocessState.stillEmpty);
      expect(stateAfter(const ReprocessUnavailable()), ReprocessState.unavailable);
      expect(stateAfter(const ReprocessFailed('x')), ReprocessState.failed);
      expect([for (final s in ReprocessState.values) s.showsButton],
          [true, true, true, false, false]);
      expect(ReprocessState.idle.message, startsWith("We couldn't finish processing"));
      expect(ReprocessState.failed.message, startsWith("Reprocessing didn't work"));
    });
  });

  group('with files', () {
    late Directory dir;
    late RecordingStore recordings;
    late SessionStore sessions;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('import_test');
      recordings = RecordingStore(baseDirectory: () async => dir);
      sessions = SessionStore(baseDirectory: () async => dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('reprocess re-analyses from the raw CSV and keeps lifter data', () async {
      final raw = recordings.relativePath(await recordings.save(_recording(60)));
      final failed = SetRecord(
        id: 's', startedAt: _start, endedAt: _start, weight: 120,
        unit: WeightUnit.kg, setType: SetType.topSet, rpe: 8, note: 'n',
        rawCsvFile: raw, sampleCount: 60, analysisError: 'boom',
        videoFile: 'videos/s.mp4', videoOffsetSec: 1.0,
      );
      List<SensorSample>? seen;
      final origin = _sample(10).hostTimeUs;
      final r = await reprocessSet(failed,
          exercise: Exercise.byId('squat_low_bar'),
          recordings: recordings,
          analyze: (samples, _) async {
            seen = samples;
            return _analysis(3, origin: origin);
          });
      expect(seen, hasLength(60));
      final set = (r as ReprocessSuccess).set;
      expect(set.reps, hasLength(3));
      expect(set.analysisError, isNull);
      expect(set.pipeline, PipelineKind.squatBenchNative);
      expect(set.measuredHz, 199.5);
      expect(set.velocityTrace, isNotEmpty);
      expect([set.weight, set.setType, set.rpe, set.note, set.rawCsvFile],
          [120, SetType.topSet, 8, 'n', raw]);
      // Offset moves from the first sample to the analysis origin (+50 ms).
      expect(set.videoOffsetSec, closeTo(1.05, 1e-9));
    });

    test('no CSV is unavailable; a bad one or an engine error fails', () async {
      final set = SetRecord(
          id: 's', startedAt: _start, endedAt: _start, weight: 0, unit: WeightUnit.kg);
      Future<ReprocessResult> run(SetRecord s, {Object? error}) => reprocessSet(s,
          exercise: Exercise.byId('squat_low_bar'),
          recordings: recordings,
          analyze: (_, _) async =>
              error == null ? _analysis(0) : throw error);
      expect(await run(set), isA<ReprocessUnavailable>());
      expect(await run(set.withRaw('recordings/missing.csv')), isA<ReprocessUnavailable>());

      final f = File('${dir.path}/recordings/empty.csv')
        ..createSync(recursive: true)
        ..writeAsStringSync('${Recording.csvHeader}\n');
      final empty = await run(set.withRaw(recordings.relativePath(f)));
      expect((empty as ReprocessFailed).message, 'No IMU data recorded — re-record the set');

      final raw = recordings.relativePath(await recordings.save(_recording(60)));
      final failed = await run(set.withRaw(raw), error: AnalysisException('too short'));
      expect((failed as ReprocessFailed).message, 'too short');
      expect(stateAfter(await run(set.withRaw(raw))), ReprocessState.stillEmpty);
    });

    test('import saves a copy of the CSV and a set in a new session', () async {
      final parsed = parseRecordingCsv(_recording(80).toCsv());
      final last = await importRecordingAsSet(parsed,
          exercise: Exercise.byId('bench_spoto'),
          weight: 90,
          unit: WeightUnit.lb,
          recordings: recordings,
          sessions: sessions,
          analyze: (_, _) async => _analysis(2));
      final all = await sessions.list();
      expect(all, hasLength(1));
      final session = all.single;
      expect(session.id, last.sessionId);
      expect(session.exerciseId, 'bench_spoto');
      expect(session.startedAt, _start.toLocal());
      final set = session.sets.single;
      expect([set.weight, set.unit, set.setType], [90, WeightUnit.lb, null]);
      expect(set.reps, hasLength(2));
      expect(set.sampleCount, 80);
      expect(set.imuQuality, isNotNull);
      expect(set.rawCsvFile, last.rawCsvFile);
      final copy = await recordings.resolve(set.rawCsvFile!);
      expect(parseRecordingCsv(copy.readAsStringSync()).samples, hasLength(80));
      expect(last.recordedAt, _start.toLocal());
      expect(last.exercise.rawValue, 'Bench press (spoto)');
    });

    test('a failed analysis still saves the set, to reprocess later', () async {
      final parsed = parseRecordingCsv(_recording(10).toCsv());
      await importRecordingAsSet(parsed,
          exercise: Exercise.byId('deadlift_sumo'),
          weight: 0,
          unit: WeightUnit.kg,
          recordings: recordings,
          sessions: sessions,
          analyze: (_, _) async => throw AnalysisException('Recording too short (10 samples)'));
      final set = (await sessions.list()).single.sets.single;
      expect(set.analysisError, 'Recording too short (10 samples)');
      expect(needsReprocessing(set), isTrue);
    });

    test('import state: clear error keeps the last import, dismiss drops it', () {
      final last = LastImportedRecording(
          exercise: Exercise.byId('squat_front'), sessionId: 'x', recordedAt: _start);
      final s = RecordingImportState(errorMessage: 'e', lastImported: last);
      expect(s.clearError().errorMessage, isNull);
      expect(s.clearError().lastImported, last);
      expect(s.dismissLast().lastImported, isNull);
      expect(s.dismissLast().errorMessage, 'e');
      expect(RecordingImportState.loading.isLoading, isTrue);
    });
  });
}

extension on SetRecord {
  SetRecord withRaw(String raw) => SetRecord(
      id: id, startedAt: startedAt, endedAt: endedAt, weight: weight,
      unit: unit, rawCsvFile: raw);
}
