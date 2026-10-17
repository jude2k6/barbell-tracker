import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/ui/exercise_list.dart';
import 'package:barbell_app/ui/feedback_sheets.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 12, 9);

Session _session(double weight) => Session(
      id: 'sess',
      exerciseId: 'squat_low_bar',
      startedAt: _t0,
      sets: [
        SetRecord(
          id: 's1',
          startedAt: _t0,
          endedAt: _t0.add(const Duration(seconds: 30)),
          weight: weight,
          unit: WeightUnit.kg,
          setType: SetType.topSet,
          reps: const [],
        ),
      ],
      tags: const [],
    );

void main() {
  testWidgets('deadlift tips appear once, after the deadlift exercises',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ListView(
              children: exerciseListChildren(context, (_) {})),
        ),
      ),
    ));
    await tester.scrollUntilVisible(find.text('Tips:'), 200);
    expect(find.byKey(const Key('deadliftTips')), findsOneWidget);
    for (final tip in deadliftTips) {
      await tester.scrollUntilVisible(find.text(tip), 200);
      expect(find.text(tip), findsOneWidget);
    }
    expect(deadliftTips.first, 'Pause between lifts (~1 second)');
  });

  for (final (weight, shown) in [(100.0, true), (0.0, false)]) {
    testWidgets('rep speed sheet help button ($weight kg)', (tester) async {
      final session = _session(weight);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRepSpeedSheet(context,
                session: session, setIndex: 0, all: [session]),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('weightPerformanceHelp')),
          shown ? findsOneWidget : findsNothing);
      if (!shown) return;
      await tester.tap(find.text('How do I use this?'));
      await tester.pumpAndSettle();
      expect(find.text('Weight Performance'), findsOneWidget);
      expect(
          find.text('Compare recent sets at any weight as an indicator of '
              'progress.'),
          findsOneWidget);
      expect(find.byKey(const Key('weightPerformanceTutorialImage')),
          findsOneWidget);
    });
  }
}
