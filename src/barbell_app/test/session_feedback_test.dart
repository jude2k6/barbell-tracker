import 'dart:io';

import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/analysis/set_analysis.dart';
import 'package:barbell_app/recording/recording.dart';
import 'package:barbell_app/ui/app_scope.dart';
import 'package:barbell_app/ui/charts/sticking_bar.dart';
import 'package:barbell_app/ui/charts/velocity_chart.dart';
import 'package:barbell_app/ui/session_feedback_page.dart';
import 'package:barbell_app/ui/weight_input_page.dart';
import 'package:barbell_app/workout/sensor_controller.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:barbell_app/workout/session_store.dart';
import 'package:barbell_app/ui/rep_check_page.dart';
import 'package:barbell_app/workout/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 12, 9);

RepRecord _rep(int i, double mean, {StickingRecord? sticking, double? rom}) =>
    RepRecord(
      index: i,
      startSec: i * 2.0 - 1,
      endSec: i * 2.0 - 0.2,
      meanVelocity: mean,
      peakVelocity: mean * 1.75,
      romMeters: rom,
      sticking: sticking,
    );

SetRecord _set(String id, double weight, List<RepRecord> reps,
        {String? error, String? video, int minute = 0}) =>
    SetRecord(
      id: id,
      startedAt: _t0.add(Duration(minutes: minute)),
      endedAt: _t0.add(Duration(minutes: minute, seconds: 30)),
      weight: weight,
      unit: WeightUnit.kg,
      setType: SetType.topSet,
      reps: reps,
      pipeline: error == null ? PipelineKind.squatBenchNative : null,
      measuredHz: error == null ? 198.6 : null,
      warnings: error == null ? const ['low sample rate'] : const [],
      analysisError: error,
      rawCsvFile: 'recordings/raw.csv',
      velocityTrace: const [0, 0.2, 0.5, 0.8, 0.4, 0, -0.3, 0, 0.3, 0.6, 0.2, 0],
      traceHz: 2,
      videoFile: video,
    );

Session _session(List<SetRecord> sets, {List<String> tags = const ['Day:Primary']}) =>
    Session(
      id: 'sess',
      exerciseId: 'squat_low_bar',
      startedAt: _t0,
      sets: sets,
      tags: tags,
    );

final _threeReps = [
  _rep(1, 0.60,
      rom: 0.55,
      sticking: const StickingRecord(
          startPct: 30, endPct: 60, minVelocityPct: 45,
          severeStartPct: 40, severeEndPct: 50)),
  _rep(2, 0.55, rom: 0.54),
  _rep(3, 0.45,
      sticking: const StickingRecord(startPct: 25, endPct: 50, minVelocityPct: 35)),
];

/// Pumps until [finder] matches, letting real file I/O complete.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

/// Lets pending store reads and writes finish.
Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// Waits [d] on both clocks: the guide timer starts after real file I/O,
/// and may land in either zone.
Future<void> _realWait(WidgetTester tester, Duration d) async {
  // Small real steps with pumps between, so chained file I/O progresses.
  for (var t = 0; t < d.inMilliseconds; t += 50) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await tester.pump(d);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Drags the set sheet up from its peek height, as a user would.
Future<void> _expandSheet(WidgetTester tester) async {
  await tester.drag(
      find.byKey(const Key('selectedSetSummary')), const Offset(0, -2000));
  await tester.pumpAndSettle();
}

void main() {
  late Directory dir;
  late SessionStore store;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('feedback_test');
    store = SessionStore(baseDirectory: () async => dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester, Session s,
      {bool active = false, PreferencesStore? prefs}) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => store.save(s));
    await tester.pumpWidget(AppScope(
      sensor: SensorController(),
      sessions: store,
      recordings: RecordingStore(baseDirectory: () async => dir),
      preferences: prefs,
      child: MaterialApp(home: SessionFeedbackPage(session: s, active: active)),
    ));
    await _settleIo(tester);
  }

  Future<Session> saved(WidgetTester tester) async =>
      (await tester.runAsync<Session?>(() => store.load('sess')))!;

  Future<void> openEdit(WidgetTester tester, {bool reps = false}) async {
    await tester.tap(find.byKey(const Key('editSet')));
    await tester.pumpAndSettle();
    if (reps) {
      await tester.tap(find.byKey(const Key('repsTab')));
      await tester.pumpAndSettle();
    }
  }

  /// A set that ended [ago] before now (default: inside the edit window).
  SetRecord fresh(List<RepRecord> reps, {Duration ago = Duration.zero}) {
    final now = DateTime.now().subtract(ago);
    final s = _set('a', 140, reps);
    return SetRecord(
      id: s.id,
      startedAt: now.subtract(const Duration(seconds: 30)),
      endedAt: now,
      weight: s.weight,
      unit: s.unit,
      setType: s.setType,
      reps: reps,
      velocityTrace: s.velocityTrace,
      traceHz: s.traceHz,
    );
  }

  testWidgets('Reps tab: Recalculate drops the smallest-ROM rep and saves',
      (tester) async {
    await open(tester, _session([fresh(_threeReps)]));
    await openEdit(tester, reps: true);
    expect(find.textContaining('left to edit'), findsOneWidget);
    expect(
        tester.widget<FilledButton>(find.byKey(const Key('recalculate'))).onPressed,
        isNull);

    await tester.enterText(find.byKey(const Key('totalReps')), '2');
    await tester.pump();
    await tester.tap(find.byKey(const Key('recalculate')));
    await tester.pump();
    await _settleIo(tester);
    // Rep 3 had no ROM (0) and goes; reps 1 and 2 stay.
    final reps = (await saved(tester)).sets.single.reps;
    expect(reps.map((r) => r.meanVelocity), [0.60, 0.55]);

    await tester.enterText(find.byKey(const Key('totalReps')), '5');
    await tester.pump();
    await tester.tap(find.byKey(const Key('recalculate')));
    await tester.pumpAndSettle();
    expect(find.text("Can't Find More Reps"), findsOneWidget);
  });

  testWidgets('rep edits are refused after the 7-day window', (tester) async {
    await open(tester, _session([fresh(_threeReps, ago: const Duration(days: 8))]));
    await openEdit(tester, reps: true);
    expect(find.text('Edit Expired'), findsOneWidget);
    await tester.tap(find.byKey(const Key('checkReps')));
    await tester.pumpAndSettle();
    expect(find.text('Edit Window Expired'), findsOneWidget);
  });

  testWidgets('Copy Set ID copies and says so', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await open(tester, _session([_set('a', 140, _threeReps)]));
    await openEdit(tester);
    await tester.tap(find.byKey(const Key('copySetId')));
    await tester.pumpAndSettle();
    expect(copied, 'a');
    expect(find.text('ID Copied'), findsOneWidget);
  });

  testWidgets('Report Issue adds, updates and deletes the set note',
      (tester) async {
    await open(tester, _session([_set('a', 140, _threeReps)]));
    await openEdit(tester);
    await tester.tap(find.byKey(const Key('reportIssue')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('addNote'))).onPressed,
        isNull);
    await tester.tap(find.byKey(const Key('dataLooksWrong')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('issueNote')), ' rep 2 missed ');
    await tester.tap(find.byKey(const Key('addNote')));
    await tester.pumpAndSettle();
    await _settleIo(tester);
    expect((await saved(tester)).sets.single.note, 'rep 2 missed');

    // Reopened with a note: "No" is preselected, so Update Note.
    await tester.tap(find.byKey(const Key('reportIssue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('updateNote')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dataLooksCorrect')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('deleteNote')));
    await tester.pumpAndSettle();
    await _settleIo(tester);
    expect((await saved(tester)).sets.single.note, isNull);
  });

  testWidgets('Rep Check deletes a rep at once and recomputes the rest',
      (tester) async {
    await open(tester, _session([fresh(_threeReps)]));
    await openEdit(tester, reps: true);
    await tester.tap(find.byKey(const Key('checkReps')));
    await tester.pumpAndSettle();
    expect(find.byType(RepCheckPage), findsOneWidget);
    // No preferences store: the rep edit guide does not auto-show.
    expect(find.byKey(const Key('guideDialog')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('deleteRep-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeleteRep')));
    await tester.pump();
    await _settleIo(tester);
    final reps = (await saved(tester)).sets.single.reps;
    expect(reps.map((r) => r.startSec), [3.0, 5.0]);
    expect(reps.map((r) => r.index), [1, 2]);
    // Unmoved: ROM kept; mean recomputed from the trace.
    expect(reps.first.romMeters, 0.54);
  });

  testWidgets('untagged: asks the session type; the answer saves the tag',
      (tester) async {
    await open(tester, _session([_set('a', 140, _threeReps)], tags: const []));
    expect(find.byKey(const Key('tagPrompt')), findsOneWidget);
    expect(find.text('What type of session are you doing today?'), findsOneWidget);
    expect(find.byKey(const Key('noComparison')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dayType-secondary')));
    await tester.pump();
    await _settleIo(tester);
    expect(find.byKey(const Key('tagPrompt')), findsNothing);
    expect((await saved(tester)).tags, ['Day:Secondary']);
    expect(find.text('Day: Secondary'), findsOneWidget);

    // The dropdown changes it, or clears it with None.
    await tester.tap(find.byKey(const Key('dayTypeDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Day: Primary').last);
    await tester.pumpAndSettle();
    await _settleIo(tester);
    expect((await saved(tester)).tags, ['Day:Primary']);
    await tester.tap(find.byKey(const Key('dayTypeDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Day: None').last);
    await tester.pumpAndSettle();
    await _settleIo(tester);
    expect((await saved(tester)).tags, isEmpty);
  });

  testWidgets('tag editor: one tag per section, saved on Done or dismiss',
      (tester) async {
    await open(tester, _session([_set('a', 140, _threeReps)], tags: const ['Day:Primary']));
    await tester.tap(find.byKey(const Key('editSessionTags')));
    await tester.pumpAndSettle();
    expect(find.text('Tags'), findsOneWidget);
    for (final s in ['Block', 'Week', 'Day', 'Externals']) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('tag-Block:7')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tagMore-Block')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('tag-Block:7')));
    await tester.tap(find.byKey(const ValueKey('tag-Block:7')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('tag-Week:2')));
    await tester.tap(find.byKey(const ValueKey('tag-Week:2')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('tag-Day:Primary')));
    await tester.tap(find.byKey(const ValueKey('tag-Day:Primary')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tagEditorDone')));
    await tester.pumpAndSettle();
    await _settleIo(tester);
    expect((await saved(tester)).tags, ['Block:7', 'Week:2']);
    // No session type now, so the question comes back.
    expect(find.byKey(const Key('tagPrompt')), findsOneWidget);

    // Dismissing keeps the edits too; the extra Block page stays open for a
    // selected tag beyond the first six.
    await tester.tap(find.byKey(const Key('editSessionTags')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-Block:7')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('tag-Externals:3')));
    await tester.tap(find.byKey(const ValueKey('tag-Externals:3')));
    await tester.pump();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await _settleIo(tester);
    expect((await saved(tester)).tags, ['Block:7', 'Week:2', 'Externals:3']);
  });

  testWidgets('dismissing the question hides it for this visit', (tester) async {
    await open(tester, _session([_set('a', 140, _threeReps)], tags: const []));
    await tester.tap(find.byKey(const Key('dismissTagPrompt')));
    await tester.pump();
    expect(find.byKey(const Key('tagPrompt')), findsNothing);
    expect((await saved(tester)).tags, isEmpty);
  });

  testWidgets('first visit shows the walkthrough, a later one a tip',
      (tester) async {
    final prefs = PreferencesStore(baseDirectory: () async => dir);
    await open(tester, _session([_set('a', 140, _threeReps)]), prefs: prefs);
    // The timer starts after real file I/O, so it runs on the real clock.
    await _realWait(tester, const Duration(milliseconds: 2200));
    expect(find.byKey(const Key('guideDialog')), findsOneWidget);
    expect(find.text('Congrats on your First Set!'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const Key('guideNext')));
      await tester.pump();
    }
    expect(find.text('Comparing Sessions'), findsOneWidget);
    await tester.tap(find.byKey(const Key('guideNext')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guideDialog')), findsNothing);
    expect(prefs.hasSeen(Guide.feedbackWalkthrough), isTrue);

    // Next visit: the readiness tip after a second, once.
    await tester.pumpWidget(const SizedBox());
    await open(tester, _session([_set('a', 140, _threeReps)]), prefs: prefs);
    await _realWait(tester, const Duration(milliseconds: 1200));
    expect(find.byKey(const Key('guideTip')), findsOneWidget);
    expect(find.textContaining('You moved 140 kg at 0.60m/s'), findsOneWidget);
    expect(prefs.hasSeen(Guide.readinessTip), isTrue);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
  });

  testWidgets('sheet shows the newest set; rep speed sheet has the details',
      (tester) async {
    await open(tester, _session([
      _set('a', 100, [_rep(1, 0.7)]),
      _set('b', 140, _threeReps, minute: 5),
    ]));

    expect(find.text('Set 2 · 140 kg · Top set · 3 reps'), findsOneWidget);
    expect(find.text('Max 0.60 · Avg 0.53 m/s · loss 25 %'), findsOneWidget);

    await _expandSheet(tester);
    await tester.tap(find.byKey(const Key('repSpeedMini')));
    await tester.pumpAndSettle();
    final chart = tester.widget<VelocityChart>(find.byType(VelocityChart));
    expect(chart.reps.map((r) => r.index), [1, 2, 3]);
    expect(tester.widget<Text>(find.byKey(const Key('pipelineLabel'))).data,
        'Squat/bench pipeline · 199 Hz');
    expect(find.text('low sample rate'), findsOneWidget);
    // Rep table: peak and ROM (cm, "–" when missing).
    expect(find.text('1.05'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);
    expect(find.text('–'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Sticking region'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.byType(StickingBar), findsNWidgets(2));
  });

  testWidgets('selecting a set chip changes the sheet', (tester) async {
    await open(tester, _session([
      _set('a', 100, [_rep(1, 0.7)]),
      _set('b', 140, _threeReps, minute: 5),
    ]));
    await tester.tap(find.byKey(const ValueKey('setChip-0')));
    await tester.pump();
    expect(find.text('Set 1 · 100 kg · Top set · 1 reps'), findsOneWidget);
  });

  testWidgets('RPE is saved from the RPE sheet and can be cleared',
      (tester) async {
    await open(tester, _session([_set('a', 140, _threeReps)]));
    expect(find.byKey(const Key('rpeCardValue')), findsNothing);

    await tester.tap(find.byKey(const Key('rpeCard')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('rpeValue'))).data, '8');
    // Right end of the slider: RPE 10.
    final box = tester.getRect(find.byKey(const Key('rpeSlider')));
    await tester.tapAt(Offset(box.right - 26, box.center.dy));
    await tester.pump();
    await tester.tap(find.byKey(const Key('rpeSave')));
    await tester.pumpAndSettle();
    await _settleIo(tester);

    expect(tester.widget<Text>(find.byKey(const Key('rpeCardValue'))).data, '10');
    final saved = await tester.runAsync<Session?>(() => store.load('sess'));
    expect(saved!.sets.single.rpe, 10);

    await tester.tap(find.byKey(const Key('rpeCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rpeClear')));
    await tester.pumpAndSettle();
    await _settleIo(tester);
    expect((await tester.runAsync<Session?>(() => store.load('sess')))!.sets.single.rpe, isNull);
  });

  testWidgets('New set only when active; it opens weight input for this session',
      (tester) async {
    await open(tester, _session([_set('a', 140, _threeReps)]));
    expect(find.byKey(const Key('newSet')), findsNothing);

    await open(tester, _session([_set('a', 140, _threeReps)]), active: true);
    await tester.tap(find.byKey(const Key('newSet')));
    await tester.pumpAndSettle();
    final page = tester.widget<WeightInputPage>(find.byType(WeightInputPage));
    expect(page.session?.id, 'sess');
    expect(page.exercise.id, 'squat_low_bar');
  });

  testWidgets('a failed analysis shows the error; no video card without video',
      (tester) async {
    await open(tester, _session([
      _set('a', 140, const [], error: 'Recording too short'),
    ]));
    expect(find.byKey(const Key('reprocessBanner')), findsOneWidget);
    expect(find.textContaining('Recording too short'), findsOneWidget);
    expect(find.textContaining('raw.csv'), findsOneWidget);
    expect(find.byKey(const Key('watchVideo')), findsNothing);
    expect(find.byKey(const Key('readinessMini')), findsNothing);

    await open(tester, _session([_set('a', 140, _threeReps, video: 'videos/a.mp4')]));
    expect(find.byKey(const Key('watchVideo')), findsOneWidget);
  });

  testWidgets('Edit Set changes weight and type; deleting the last set '
      'deletes the session', (tester) async {
    await open(tester, _session([
      _set('a', 100, [_rep(1, 0.7)]),
      _set('b', 140, _threeReps, minute: 5),
    ]));

    await tester.tap(find.byKey(const Key('editSet')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('editWeight')), '142.5');
    await tester.tap(find.text('Backoff'));
    await tester.tap(find.byKey(const Key('editDone')));
    await tester.pumpAndSettle();
    await _settleIo(tester);

    var saved = (await tester.runAsync<Session?>(() => store.load('sess')))!;
    expect(saved.sets.last.weight, 142.5);
    expect(saved.sets.last.setType, SetType.backoff);
    expect(find.text('Set 2 · 142.5 kg · Backoff · 3 reps'), findsOneWidget);

    Future<void> deleteSelected() async {
      await tester.tap(find.byKey(const Key('editSet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteSet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDeleteSet')));
      await tester.pumpAndSettle();
      await _settleIo(tester);
    }

    await deleteSelected();
    saved = (await tester.runAsync<Session?>(() => store.load('sess')))!;
    expect(saved.sets.map((s) => s.id), ['a']);
    await _pumpUntil(tester, find.text('Set 1 · 100 kg · Top set · 1 reps'));

    await deleteSelected();
    expect(await tester.runAsync<Session?>(() => store.load('sess')), isNull);
  });
}
