import 'dart:async';
import 'dart:io';

import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/analysis/set_analysis.dart';
import 'package:barbell_app/recording/recording.dart';
import 'package:barbell_app/sensor/sensor_sample.dart';
import 'package:barbell_app/ui/app_scope.dart';
import 'package:barbell_app/ui/recording_import_card.dart';
import 'package:barbell_app/ui/session_feedback_page.dart';
import 'package:barbell_app/workout/analysis_runner.dart';
import 'package:barbell_app/workout/sensor_controller.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:barbell_app/workout/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 12, 9);

Recording _recording(int n) =>
    Recording(sensorName: 'WT', startedAt: _t0)
      ..samples.addAll([
        for (var i = 0; i < n; i++)
          SensorSample(
            hostTimeUs: _t0.microsecondsSinceEpoch + i * 5000,
            sensorTimeMs: null,
            ax: 0, ay: 0, az: 1, gx: 0, gy: 0, gz: 0,
            q0: 1, q1: 0, q2: 0, q3: 0,
          ),
      ]);

SetAnalysis _analysis(int reps) => SetAnalysis(
      reps: [
        for (var i = 1; i <= reps; i++)
          RepResult(index: i, startSec: i * 2.0, endSec: i * 2.0 + 0.8,
              meanVelocity: 0.5, peakVelocity: 0.9, romMeters: 0.5),
      ],
      velocity: List.filled(400, 0.1),
      velocityHz: 200,
      measuredHz: 200,
      pipeline: PipelineKind.squatBenchNative,
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// Pumps until [finder] matches, letting real file I/O complete.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

void main() {
  late Directory dir;
  late SessionStore store;
  late RecordingStore recordings;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('reprocess_ui_test');
    store = SessionStore(baseDirectory: () async => dir);
    recordings = RecordingStore(baseDirectory: () async => dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Widget scope(Widget home, SetAnalyzer analyzer) => AppScope(
        sensor: SensorController(),
        sessions: store,
        recordings: recordings,
        analyzer: analyzer,
        child: MaterialApp(home: home),
      );

  group('reprocess banner', () {
    Future<Session> session(WidgetTester tester, {bool withCsv = true}) async {
      final raw = withCsv
          ? await tester.runAsync(() async =>
              recordings.relativePath(await recordings.save(_recording(100))))
          : 'recordings/gone.csv';
      final s = Session(id: 'sess', exerciseId: 'squat_low_bar', startedAt: _t0, sets: [
        SetRecord(id: 'a', startedAt: _t0, endedAt: _t0, weight: 140,
            unit: WeightUnit.kg, setType: SetType.topSet, rpe: 8,
            rawCsvFile: raw, analysisError: 'Recording too short'),
      ], tags: const ['Day:Primary']);
      await tester.runAsync(() => store.save(s));
      return s;
    }

    Future<void> open(WidgetTester tester, Session s, SetAnalyzer analyzer) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(scope(SessionFeedbackPage(session: s), analyzer));
      await _settle(tester);
    }

    testWidgets('Reprocess runs from the raw CSV; with reps the banner goes',
        (tester) async {
      final done = Completer<SetAnalysis>();
      var calls = 0;
      await open(tester, await session(tester), (samples, _) {
        calls++;
        expect(samples, hasLength(100));
        return done.future;
      });
      expect(find.text("We couldn't finish processing this set. "
          'Your data is safe and already backed up.'), findsOneWidget);
      expect(find.textContaining('Recording too short'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reprocessButton')));
      await _settle(tester);
      expect(find.text('Reprocessing…'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reprocessButton')));
      expect(calls, 1);

      done.complete(_analysis(3));
      await _pumpUntil(tester, find.text('Set 1 · 140 kg · Top set · 3 reps'));
      expect(find.byKey(const Key('reprocessBanner')), findsNothing);
      expect(find.text('Set 1 · 140 kg · Top set · 3 reps'), findsOneWidget);
      await _settle(tester);
      final saved = (await tester.runAsync(() => store.load('sess')))!.sets.single;
      expect(saved.reps, hasLength(3));
      expect(saved.analysisError, isNull);
      expect(saved.rpe, 8);
    });

    testWidgets('no reps again: "still empty", no button', (tester) async {
      await open(tester, await session(tester), (_, _) async => _analysis(0));
      await tester.tap(find.byKey(const Key('reprocessButton')));
      await _pumpUntil(tester, find.textContaining('We still'));
      expect(find.text("We still couldn't find reps in this set. "
          'Your data is backed up for review.'), findsOneWidget);
      expect(find.byKey(const Key('reprocessButton')), findsNothing);
    });

    testWidgets('engine error: "didn\'t work", can try again', (tester) async {
      await open(tester, await session(tester),
          (_, _) async => throw AnalysisException('nope'));
      await tester.tap(find.byKey(const Key('reprocessButton')));
      await _pumpUntil(tester, find.textContaining("didn't work"));
      expect(find.text("Reprocessing didn't work this time. You can try again."),
          findsOneWidget);
      expect(find.byKey(const Key('reprocessButton')), findsOneWidget);
    });

    testWidgets('CSV gone: unavailable, no button', (tester) async {
      await open(tester, await session(tester, withCsv: false), (_, _) async => _analysis(2));
      await tester.tap(find.byKey(const Key('reprocessButton')));
      await _pumpUntil(tester, find.textContaining('available right after'));
      expect(find.textContaining('Reprocessing is available right after recording.'),
          findsOneWidget);
      expect(find.byKey(const Key('reprocessButton')), findsNothing);
    });
  });

  group('Home import card', () {
    testWidgets('pick → exercise and weight → set saved, label shown', (tester) async {
      String? shared;
      await tester.pumpWidget(scope(
        Scaffold(
          body: RecordingImportCard(
            pick: () async => (name: 'set.csv', text: _recording(80).toCsv()),
            share: (p) async => shared = p,
          ),
        ),
        (_, _) async => _analysis(2),
      ));
      expect(find.text('Import recording'), findsOneWidget);
      await tester.tap(find.byKey(const Key('importRecording')));
      await tester.pumpAndSettle();
      expect(find.text('set.csv'), findsOneWidget);
      expect(
          tester.widget<FilledButton>(find.byKey(const Key('importContinue'))).onPressed,
          isNull);

      await tester.tap(find.byKey(const Key('importExercise')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Squat (front)').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('importWeight')), '102.5');
      await tester.pump();
      await tester.tap(find.byKey(const Key('importContinue')));
      await tester.pump();
      await _pumpUntil(tester, find.byKey(const Key('lastImported')));

      expect(find.text('Imported: Squat (front)'), findsOneWidget);
      expect(find.textContaining('Recorded: '), findsOneWidget);
      expect(find.text('Tap to open Sessions for this exercise'), findsOneWidget);
      final saved = (await tester.runAsync(() => store.list()))!.single;
      expect(saved.exerciseId, 'squat_front');
      expect(saved.sets.single.weight, 102.5);
      expect(saved.sets.single.reps, hasLength(2));

      await tester.tap(find.byKey(const Key('exportImuCsv')));
      await _settle(tester);
      expect(shared, endsWith('.csv'));

      await tester.tap(find.byKey(const Key('dismissLastImport')));
      await tester.pump();
      expect(find.byKey(const Key('lastImported')), findsNothing);
    });

    testWidgets("a bad file shows Stance's error; nothing saved", (tester) async {
      await tester.pumpWidget(scope(
        Scaffold(
          body: RecordingImportCard(pick: () async => (name: 'x.txt', text: 'hello\n')),
        ),
        (_, _) async => _analysis(2),
      ));
      await tester.tap(find.byKey(const Key('importRecording')));
      await tester.pumpAndSettle();
      expect(find.text('Unexpected CSV header. Expected exact export header line.'),
          findsOneWidget);
      expect(await tester.runAsync(() => store.list()), isEmpty);
    });
  });
}
