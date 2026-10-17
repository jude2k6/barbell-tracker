import 'dart:io';

import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/recording/recording.dart';
import 'package:barbell_app/ui/app_scope.dart';
import 'package:barbell_app/ui/exercise_list.dart';
import 'package:barbell_app/ui/home_page.dart';
import 'package:barbell_app/ui/record_set_page.dart';
import 'package:barbell_app/ui/session_feedback_page.dart';
import 'package:barbell_app/ui/sessions_page.dart';
import 'package:barbell_app/ui/weight_input_page.dart';
import 'package:barbell_app/ui/workout_flow.dart';
import 'package:barbell_app/workout/active_session.dart';
import 'package:barbell_app/workout/preferences.dart';
import 'package:barbell_app/workout/sensor_controller.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:barbell_app/workout/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SetRecord _set(String id, DateTime end, {double weight = 100}) => SetRecord(
      id: id,
      startedAt: end.subtract(const Duration(seconds: 30)),
      endedAt: end,
      weight: weight,
      unit: WeightUnit.kg,
      reps: const [
        RepRecord(index: 1, startSec: 0, endSec: 1, meanVelocity: 0.5, peakVelocity: 0.9),
      ],
    );

Session _session(String id, DateTime end, {String exercise = 'squat_low_bar'}) =>
    Session(
      id: id,
      exerciseId: exercise,
      startedAt: end.subtract(const Duration(minutes: 10)),
      sets: [_set('$id-1', end)],
    );

Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// Finishes a route transition without pumpAndSettle: the Sessions page
/// spins until its (real) file I/O completes.
Future<void> _navigate(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await _settleIo(tester);
}

/// Pumps until [finder] matches, letting real file I/O complete.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

void main() {
  group('activeSessionId (Stance ActiveSessionPolicy)', () {
    final now = DateTime(2026, 10, 17, 18, 0);

    test('newest session of the exercise, same day, ended < 1 h ago', () {
      final sessions = [
        _session('old', now.subtract(const Duration(hours: 3))),
        _session('recent', now.subtract(const Duration(minutes: 59))),
        _session('bench', now.subtract(const Duration(minutes: 5)),
            exercise: 'bench_spoto'),
      ];
      expect(activeSessionId(sessions, 'squat_low_bar', now: now), 'recent');
      expect(activeSessionId(sessions, 'bench_spoto', now: now), 'bench');
      expect(activeSessionId(sessions, 'deadlift_sumo', now: now), isNull);
    });

    test('an hour or more ago, or another day, is not active', () {
      expect(
          activeSessionId([_session('s', now.subtract(const Duration(minutes: 60)))],
              'squat_low_bar', now: now),
          isNull);
      final justAfterMidnight = DateTime(2026, 10, 18, 0, 10);
      expect(
          activeSessionId([_session('s', DateTime(2026, 10, 17, 23, 50))],
              'squat_low_bar', now: justAfterMidnight),
          isNull);
    });

    test('only the newest counts', () {
      // The newest ended 2 h ago; an older one cannot be active.
      final sessions = [
        _session('newest', now.subtract(const Duration(hours: 2))),
      ];
      expect(activeSessionId(sessions, 'squat_low_bar', now: now), isNull);
    });

    test('session end is the end stamp, else the last set', () {
      final s = _session('s', DateTime(2026, 10, 17, 9));
      expect(sessionEnd(s), DateTime(2026, 10, 17, 9));
      expect(sessionEnd(s.copyWith(endedAt: DateTime(2026, 10, 17, 10))),
          DateTime(2026, 10, 17, 10));
    });
  });

  group('screens', () {
    late Directory dir;
    late SessionStore store;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('flow_test');
      store = SessionStore(baseDirectory: () async => dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Widget app(Widget home, {PreferencesStore? prefs}) => AppScope(
          sensor: SensorController(),
          sessions: store,
          recordings: RecordingStore(baseDirectory: () async => dir),
          preferences: prefs,
          child: MaterialApp(home: home),
        );

    testWidgets('Home lists the groups; a group lists its exercises; '
        'tapping one opens its Sessions', (tester) async {
      await tester.pumpWidget(app(const HomePage()));
      expect(find.text('Exercise'), findsOneWidget);
      for (final f in ExerciseFamily.values) {
        final group = find.byKey(ValueKey('group-${f.name}'));
        await tester.scrollUntilVisible(group, 200);
        await tester.pump();
        await tester.tap(group);
        await tester.pump();
        expect(find.text(familyTitle(f)), findsOneWidget);
        for (final e in Exercise.all.where((e) => e.family == f)) {
          final tile = find.byKey(ValueKey('exercise-${e.id}'));
          await tester.scrollUntilVisible(tile, 200);
          // ensureVisible jumps without a frame; lay out before the next step.
          await tester.pump();
          expect(tile, findsOneWidget);
        }
        if (f != ExerciseFamily.deadlift) {
          await tester.tap(find.byKey(const Key('homeBack')));
          await tester.pump();
          expect(find.text('Exercise'), findsOneWidget);
        }
      }
      final sumo = find.byKey(const ValueKey('exercise-deadlift_sumo'));
      await tester.scrollUntilVisible(sumo, -200);
      await tester.pump();
      await tester.tap(sumo);
      await _navigate(tester);
      expect(tester.widget<SessionsPage>(find.byType(SessionsPage)).exercise.id,
          'deadlift_sumo');
      await _pumpUntil(tester, find.text('Tap new session to start collecting data.'));
    });

    testWidgets('Sessions: Continue on the active one, View on the rest',
        (tester) async {
      final now = DateTime(2026, 10, 17, 18);
      await tester.runAsync(() async {
        await store.save(_session('today', now.subtract(const Duration(minutes: 20)))
            .copyWith(tags: ['Day:Primary']));
        await store.save(_session('earlier', now.subtract(const Duration(days: 2))));
        await store.save(_session('bench', now, exercise: 'bench_spoto'));
      });
      await tester.pumpWidget(app(SessionsPage(
          exercise: Exercise.byId('squat_low_bar'), now: () => now)));
      await _pumpUntil(tester, find.byKey(const ValueKey('openSession-earlier')));

      expect(find.byKey(const ValueKey('sessionCard-bench')), findsNothing);
      Text label(String id) => tester.widget<Text>(find.descendant(
          of: find.byKey(ValueKey('openSession-$id')), matching: find.byType(Text)));
      expect(label('today').data, 'Continue');
      expect(label('earlier').data, 'View');
      expect(find.descendant(
              of: find.byKey(const ValueKey('sessionTags-today')),
              matching: find.text('Primary')),
          findsOneWidget);
      expect(find.descendant(
              of: find.byKey(const ValueKey('sessionTags-earlier')),
              matching: find.byType(Chip)),
          findsNothing);

      await tester.tap(find.byKey(const ValueKey('openSession-today')));
      await _navigate(tester);
      final page = tester.widget<SessionFeedbackPage>(find.byType(SessionFeedbackPage));
      expect(page.session.id, 'today');
      expect(page.active, isTrue);
    });

    testWidgets('weight input needs a weight and a set type; unit from '
        'Preferences', (tester) async {
      final prefs = PreferencesStore(baseDirectory: () async => dir);
      prefs.value = const Preferences(weightUnit: WeightUnit.lb);
      await tester.pumpWidget(app(
          WeightInputPage(exercise: Exercise.byId('squat_low_bar')),
          prefs: prefs));
      await _settleIo(tester);

      FilledButton continueButton() =>
          tester.widget<FilledButton>(find.descendant(
              of: find.byKey(const Key('continue')),
              matching: find.byType(FilledButton)));
      expect(find.text('This value is saved in pounds (lb).'), findsOneWidget);
      expect(continueButton().onPressed, isNull);
      await tester.enterText(find.byKey(const Key('weightField')), '225');
      await tester.pump();
      expect(continueButton().onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('setType-top_set')));
      await tester.pump();
      expect(continueButton().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('continue')));
      await tester.pumpAndSettle();
      final record = tester.widget<RecordSetPage>(find.byType(RecordSetPage));
      expect(record.weight, 225);
      expect(record.unit, WeightUnit.lb);
      expect(record.setType, SetType.topSet);
      expect(record.session, isNull);
      expect(find.text('225 lb'), findsOneWidget);
      expect(find.text('Top set'), findsOneWidget);
    });

    testWidgets('weight starts at the last weight, converted to the unit',
        (tester) async {
      await tester.runAsync(() => store.setLastWeight(
          'squat_low_bar', const LastWeight(100, WeightUnit.kg)));
      final prefs = PreferencesStore(baseDirectory: () async => dir);
      prefs.value = const Preferences(weightUnit: WeightUnit.lb);
      await tester.pumpWidget(app(
          WeightInputPage(exercise: Exercise.byId('squat_low_bar')),
          prefs: prefs));
      await _settleIo(tester);
      expect(
          tester.widget<TextField>(find.byKey(const Key('weightField')))
              .controller!.text,
          '220.5');
    });

    /// Home → Sessions → [pages] on top, then [showFeedbackAfterSet].
    Future<NavigatorState> stack(WidgetTester tester) async {
      await tester.pumpWidget(app(const HomePage()));
      await tester.tap(find.byKey(const ValueKey('group-squat')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('exercise-squat_low_bar')));
      await _navigate(tester);
      return tester.state<NavigatorState>(find.byType(Navigator));
    }

    testWidgets('first set of a new session: feedback replaces weight and '
        'record, back goes to Sessions', (tester) async {
      final nav = await stack(tester);
      final s = _session('new', DateTime.now());
      await tester.runAsync(() => store.save(s));
      nav.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('weight'))));
      nav.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('record'))));
      await _navigate(tester);

      showFeedbackAfterSet(tester.element(find.text('record')), s, continuing: false);
      await _navigate(tester);
      expect(tester.widget<SessionFeedbackPage>(find.byType(SessionFeedbackPage)).active,
          isTrue);

      nav.pop();
      await _navigate(tester);
      expect(find.byType(SessionsPage), findsOneWidget);
      expect(find.text('weight'), findsNothing);
    });

    testWidgets('a set added from feedback returns to that feedback page',
        (tester) async {
      final nav = await stack(tester);
      final s = _session('live', DateTime.now());
      await tester.runAsync(() => store.save(s));
      openSessionFeedback(tester.element(find.byType(SessionsPage)), s, active: true);
      await _navigate(tester);
      nav.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('weight'))));
      nav.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('record'))));
      await _navigate(tester);

      // The record page saved a second set.
      final updated = s.copyWith(sets: [...s.sets, _set('live-2', DateTime.now())]);
      await tester.runAsync(() => store.save(updated));
      showFeedbackAfterSet(tester.element(find.text('record')), updated,
          continuing: true);
      await _navigate(tester);

      expect(find.text('record'), findsNothing);
      expect(find.text('weight'), findsNothing);
      expect(find.byType(SessionFeedbackPage), findsOneWidget);
      // It reloaded and selected the new set.
      await _pumpUntil(tester, find.bySemanticsLabel(RegExp(r'^Set 2 · 100 kg')));
      expect(
          tester.widget<Semantics>(find.byKey(const Key('selectedSetSummary')))
              .properties
              .label,
          startsWith('Set 2 '));
    });
  });
}
