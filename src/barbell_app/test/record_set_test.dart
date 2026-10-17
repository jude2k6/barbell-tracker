import 'dart:async';
import 'dart:io';

import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/analysis/set_analysis.dart';
import 'package:barbell_app/recording/recording.dart';
import 'package:barbell_app/sensor/sensor_sample.dart';
import 'package:barbell_app/ui/app_scope.dart';
import 'package:barbell_app/ui/guides.dart';
import 'package:barbell_app/ui/record_set_page.dart';
import 'package:barbell_app/workout/preferences.dart';
import 'package:barbell_app/workout/sensor_controller.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:barbell_app/workout/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sensor_link.dart';

void main() {
  late Directory dir;
  late SessionStore store;
  late PreferencesStore prefs;
  late SensorController sensor;
  late FakeSensorLink link;
  late Completer<SetAnalysis> analysis;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('record_test');
    store = SessionStore(baseDirectory: () async => dir);
    prefs = PreferencesStore(baseDirectory: () async => dir);
    sensor = SensorController();
    link = FakeSensorLink();
    analysis = Completer();
  });
  tearDown(() {
    sensor.dispose();
    dir.deleteSync(recursive: true);
  });

  /// A host page with a button that opens the record page for [exercise].
  Future<void> host(WidgetTester tester, {String exercise = 'squat_low_bar'}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => sensor.connect(link));
    await tester.pumpWidget(AppScope(
      sensor: sensor,
      sessions: store,
      recordings: RecordingStore(baseDirectory: () async => dir),
      preferences: prefs,
      analyzer: (List<SensorSample> samples, Exercise e) => analysis.future,
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RecordSetPage(
                exercise: Exercise.byId(exercise),
                weight: 100,
                unit: WeightUnit.kg,
                setType: SetType.topSet,
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('setup guide on the first visit only; deadlift placement',
      (tester) async {
    await host(tester, exercise: 'deadlift_sumo');
    expect(find.text('Get Set Up in 30 Seconds'), findsOneWidget);
    // A tip from the deadlift pool sits under the guide.
    final tip = tester.widget<Text>(find.descendant(
        of: find.byKey(const Key('recordingTip')), matching: find.byType(Text)).last);
    expect(preRecordingTipPool(ExerciseFamily.deadlift), contains(tip.data));
    expect(preRecordingTipPool(ExerciseFamily.deadlift).join(),
        isNot(contains('re-rack')));
    await tester.tap(find.byKey(const Key('guideNext')));
    await tester.pump();
    expect(find.text('Tracker Attachment (Deadlift)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('guideNext')));
    await tester.pump();
    expect(find.text('Ready to Record'), findsOneWidget);
    await tester.tap(find.text('Ready to Record'));
    await tester.pumpAndSettle();
    expect(prefs.hasSeen(Guide.preRecordingGuide), isTrue);

    Navigator.of(tester.element(find.byType(RecordSetPage))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guideDialog')), findsNothing);
    // Still available from the top bar.
    await tester.tap(find.byKey(const Key('setupGuide')));
    await tester.pumpAndSettle();
    expect(find.text('Get Set Up in 30 Seconds'), findsOneWidget);
  });

  testWidgets('analysis counts down from 60 s; leaving still saves the set',
      (tester) async {
    await tester.runAsync(() => prefs.markSeen(Guide.preRecordingGuide));
    await host(tester);

    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      link.emit(i);
    }
    // The controller re-broadcasts asynchronously on the real event loop.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    // Live signal badge beside the button (fake samples are 5 ms apart).
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.descendant(
        of: find.byKey(const Key('signalQualityBadge')),
        matching: find.text('Good')), findsOneWidget);
    expect(find.text('200 pkt/s'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recordButton')));
    // Raw CSV save is real file I/O.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.byKey(const Key('analysisCountdown')), findsOneWidget);
    expect(find.text('60s left'), findsOneWidget);
    expect(find.text('You can leave this screen — your set will still be saved.'),
        findsOneWidget);

    // Leave while it analyses.
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RecordSetPage), findsNothing);

    analysis.complete(const SetAnalysis(
      reps: [
        RepResult(
            index: 1,
            startSec: 0,
            endSec: 0.05,
            meanVelocity: 0.5,
            peakVelocity: 0.8,
            romMeters: 0.5),
      ],
      velocity: [0, 0.5, 0],
      velocityHz: 50,
      measuredHz: 200,
      pipeline: PipelineKind.squatBenchNative,
    ));
    List<Session> sessions = const [];
    for (var i = 0; i < 50 && sessions.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      sessions = (await tester.runAsync(store.list))!;
    }
    expect(sessions.single.sets.single.reps.single.meanVelocity, 0.5);
    expect(sessions.single.sets.single.weight, 100);
    expect(sessions.single.sets.single.imuQuality?.imuDataLossPct, 0);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
