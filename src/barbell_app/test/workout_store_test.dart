import 'dart:convert';
import 'dart:io';

import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/analysis/set_analysis.dart';
import 'package:barbell_app/recording/recording.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:barbell_app/workout/session_recorder.dart';
import 'package:barbell_app/workout/session_store.dart';
import 'package:barbell_app/workout/set_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

RepRecord rep(int i, double mean, {StickingRecord? sticking, double? rom}) =>
    RepRecord(
      index: i,
      startSec: i * 2.0,
      endSec: i * 2.0 + 0.8,
      meanVelocity: mean,
      peakVelocity: mean * 1.6,
      romMeters: rom,
      sticking: sticking,
    );

SetRecord fullSet() => SetRecord(
      id: 'set-1',
      startedAt: DateTime.utc(2026, 10, 12, 9, 30, 0, 123),
      endedAt: DateTime.utc(2026, 10, 12, 9, 30, 25),
      weight: 142.5,
      unit: WeightUnit.lb,
      setType: SetType.topSet,
      rpe: 8.5,
      note: 'grindy last rep',
      reps: [
        rep(1, 0.61, rom: 0.52),
        rep(2, 0.55,
            rom: 0.51,
            sticking: const StickingRecord(
              startPct: 30,
              endPct: 55.5,
              minVelocityPct: 42,
              severeStartPct: 38,
              severeEndPct: 47,
            )),
        rep(3, 0.48,
            sticking: const StickingRecord(startPct: 20, endPct: 40)),
      ],
      pipeline: PipelineKind.squatBenchNative,
      warnings: const ['low sample rate'],
      measuredHz: 187.4,
      rawCsvFile: 'recordings/2026-10-12T09-30-00.123Z.csv',
      sampleCount: 4680,
    );

void main() {
  group('JSON round-trip', () {
    test('full session survives encode/decode', () {
      final session = Session(
        id: 's1',
        exerciseId: 'squat_low_bar',
        startedAt: DateTime.utc(2026, 10, 12, 9, 0),
        endedAt: DateTime.utc(2026, 10, 12, 10, 0),
        sets: [fullSet()],
      );
      final decoded = Session.fromJson(
          jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>);

      expect(decoded.id, 's1');
      expect(decoded.exerciseId, 'squat_low_bar');
      expect(decoded.exercise?.rawValue, 'Squat (low bar)');
      expect(decoded.startedAt.isAtSameMomentAs(session.startedAt), isTrue);
      expect(decoded.endedAt!.isAtSameMomentAs(session.endedAt!), isTrue);
      expect(decoded.sets, hasLength(1));

      final s = decoded.sets.single;
      final o = session.sets.single;
      expect(s.id, o.id);
      expect(s.startedAt.isAtSameMomentAs(o.startedAt), isTrue);
      expect(s.endedAt.isAtSameMomentAs(o.endedAt), isTrue);
      expect(s.weight, 142.5);
      expect(s.unit, WeightUnit.lb);
      expect(s.setType, SetType.topSet);
      expect(s.rpe, 8.5);
      expect(s.note, 'grindy last rep');
      expect(s.pipeline, PipelineKind.squatBenchNative);
      expect(s.warnings, ['low sample rate']);
      expect(s.measuredHz, 187.4);
      expect(s.rawCsvFile, o.rawCsvFile);
      expect(s.sampleCount, 4680);
      expect(s.analysisError, isNull);

      expect(s.reps, hasLength(3));
      expect(s.reps[0].romMeters, 0.52);
      expect(s.reps[0].sticking, isNull);
      expect(s.reps[1].index, 2);
      expect(s.reps[1].startSec, 4.0);
      expect(s.reps[1].endSec, closeTo(4.8, 1e-12));
      expect(s.reps[1].meanVelocity, 0.55);
      expect(s.reps[1].peakVelocity, closeTo(0.88, 1e-12));
      final st = s.reps[1].sticking!;
      expect(st.startPct, 30);
      expect(st.endPct, 55.5);
      expect(st.minVelocityPct, 42);
      expect(st.severeStartPct, 38);
      expect(st.severeEndPct, 47);
      expect(st.hasSevere, isTrue);
      expect(s.reps[2].romMeters, isNull);
      expect(s.reps[2].sticking!.minVelocityPct, isNull);
      expect(s.reps[2].sticking!.hasSevere, isFalse);
    });

    test('failed-analysis set with minimal fields', () {
      final set = SetRecord(
        id: 'x',
        startedAt: DateTime.utc(2026),
        endedAt: DateTime.utc(2026),
        weight: 60,
        unit: WeightUnit.kg,
        analysisError: 'Recording too short',
      );
      final json = set.toJson();
      expect(json.containsKey('rpe'), isFalse);
      expect(json.containsKey('pipeline'), isFalse);
      final back = SetRecord.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(back.setType, isNull);
      expect(back.rpe, isNull);
      expect(back.note, isNull);
      expect(back.reps, isEmpty);
      expect(back.pipeline, isNull);
      expect(back.measuredHz, isNull);
      expect(back.analysisError, 'Recording too short');
    });

    test('integer-valued numbers decode as doubles', () {
      final back = SetRecord.fromJson(jsonDecode(
              '{"id":"a","startedAt":"2026-01-01T00:00:00Z",'
              '"endedAt":"2026-01-01T00:00:00Z","weight":100,"unit":"kg",'
              '"rpe":9,"reps":[{"index":1,"startSec":1,"endSec":2,'
              '"meanVelocity":1,"peakVelocity":2}]}')
          as Map<String, dynamic>);
      expect(back.weight, 100.0);
      expect(back.rpe, 9.0);
      expect(back.reps.single.meanVelocity, 1.0);
    });

    test('RepRecord.fromResult copies analysis output', () {
      const r = RepResult(
        index: 1,
        startSec: 0.5,
        endSec: 1.2,
        meanVelocity: 0.4,
        peakVelocity: 0.7,
        romMeters: null,
        sticking: StickingRegion(startPct: 10, endPct: 20, minVelocityPct: 15),
      );
      final rec = RepRecord.fromResult(r);
      expect(rec.romMeters, isNull);
      expect(rec.sticking!.minVelocityPct, 15);
      expect(rec.sticking!.severeStartPct, isNull);
    });

    test('unknown exercise id still loads', () {
      final s = Session.fromJson({
        'id': 'q',
        'exerciseId': 'zercher',
        'startedAt': '2026-01-01T00:00:00Z',
      });
      expect(s.exercise, isNull);
      expect(s.exerciseTitle, 'zercher');
    });
  });

  group('metrics', () {
    test('best, average and velocity loss', () {
      final reps = [rep(1, 0.50), rep(2, 0.60), rep(3, 0.45)];
      expect(reps.bestMeanVelocity, 0.60);
      expect(reps.avgMeanVelocity, closeTo(0.5167, 1e-4));
      expect(reps.velocityLossPct, closeTo(25, 1e-9));
    });

    test('loss is null for one rep and zero if last is fastest', () {
      expect([rep(1, 0.5)].velocityLossPct, isNull);
      expect([rep(1, 0.4), rep(2, 0.5)].velocityLossPct, 0);
      expect(<RepRecord>[].bestMeanVelocity, isNull);
    });
  });

  group('SessionStore', () {
    late Directory tmp;
    late SessionStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('session_store_test');
      store = SessionStore(baseDirectory: () async => tmp);
    });

    tearDown(() async => tmp.delete(recursive: true));

    Session session(String id, DateTime started) => Session(
          id: id,
          exerciseId: 'bench_competition',
          startedAt: started,
          sets: [fullSet()],
        );

    test('save, load, list newest first, delete', () async {
      var notified = 0;
      store.addListener(() => notified++);

      await store.save(session('old', DateTime.utc(2026, 1, 1)));
      await store.save(session('new', DateTime.utc(2026, 6, 1)));
      expect(File('${tmp.path}/sessions/old.json').existsSync(), isTrue);

      final loaded = await store.load('new');
      expect(loaded!.sets.single.reps, hasLength(3));
      expect(await store.load('missing'), isNull);

      final all = await store.list();
      expect(all.map((s) => s.id), ['new', 'old']);

      await store.delete('old');
      expect((await store.list()).map((s) => s.id), ['new']);
      expect(notified, 3);
    });

    test('overwriting a session replaces it', () async {
      final s = session('a', DateTime.utc(2026));
      await store.save(s);
      await store.save(s.copyWith(sets: []));
      expect((await store.load('a'))!.sets, isEmpty);
      expect(await store.list(), hasLength(1));
    });

    test('corrupt files are skipped', () async {
      await store.save(session('good', DateTime.utc(2026)));
      await File('${tmp.path}/sessions/bad.json').writeAsString('{not json');
      expect((await store.list()).map((s) => s.id), ['good']);
    });

    test('remembers last weight per exercise', () async {
      expect(await store.lastWeight('squat_front'), isNull);
      await store.setLastWeight('squat_front', const LastWeight(100, WeightUnit.kg));
      await store.setLastWeight('bench_spoto', const LastWeight(225, WeightUnit.lb));
      final squat = await store.lastWeight('squat_front');
      final bench = await store.lastWeight('bench_spoto');
      expect(squat!.weight, 100);
      expect(squat.unit, WeightUnit.kg);
      expect(bench!.weight, 225);
      expect(bench.unit, WeightUnit.lb);
    });

    test('SessionRecorder writes on the first set and stamps its end',
        () async {
      final exercise = Exercise.byId('deadlift_sumo');
      SessionRecorder(store: store, exercise: exercise);
      expect(await store.list(), isEmpty);

      final rec = SessionRecorder(store: store, exercise: exercise);
      await rec.addSet(fullSet());
      final saved = (await store.list()).single;
      expect(saved.endedAt!.isAtSameMomentAs(fullSet().endedAt), isTrue);
      expect(saved.exerciseId, 'deadlift_sumo');
      expect((await store.lastWeight('deadlift_sumo'))!.weight, 142.5);
    });

    test('SessionRecorder continues a session and keeps edits made since',
        () async {
      final exercise = Exercise.byId('deadlift_sumo');
      final first = await SessionRecorder(store: store, exercise: exercise)
          .addSet(fullSet());
      // An RPE edited on the feedback page after the recorder was opened.
      final rec = SessionRecorder(store: store, exercise: exercise, existing: first);
      await store.save(first.replaceSet(first.sets.single.copyWith(rpe: 8)));

      final later = SetRecord(
        id: 'set-2',
        startedAt: DateTime.utc(2026, 10, 12, 9, 35),
        endedAt: DateTime.utc(2026, 10, 12, 9, 35, 30),
        weight: 150,
        unit: WeightUnit.lb,
      );
      await rec.addSet(later);
      final saved = (await store.list()).single;
      expect(saved.id, first.id);
      expect(saved.sets.map((s) => s.id), ['set-1', 'set-2']);
      expect(saved.sets.first.rpe, 8);
      expect(saved.endedAt!.isAtSameMomentAs(later.endedAt), isTrue);
    });
  });

  group('RecordingStore', () {
    test('saves CSV under injected base and resolves relative path', () async {
      final tmp = await Directory.systemTemp.createTemp('recording_store_test');
      addTearDown(() => tmp.delete(recursive: true));
      final store = RecordingStore(baseDirectory: () async => tmp);
      final r = Recording(sensorName: 'WT901', startedAt: DateTime.utc(2026, 10, 12));
      final file = await store.save(r);
      final rel = store.relativePath(file);
      expect(rel, startsWith('recordings/'));
      expect(rel, endsWith('.csv'));
      final resolved = await store.resolve(rel);
      expect(resolved.readAsStringSync(), contains(Recording.csvHeader));
      expect(await store.list(), hasLength(1));
    });
  });
}
