import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/ui/readiness_card.dart';
import 'package:barbell_app/workout/readiness.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _ids = 0;

SetRecord _set(double weight, List<double> velocities,
    {WeightUnit unit = WeightUnit.kg, SetType? type, String? error}) {
  final t = DateTime.utc(2026, 10, 12, 9);
  return SetRecord(
    id: 'set${_ids++}',
    startedAt: t,
    endedAt: t,
    weight: weight,
    unit: unit,
    setType: type,
    analysisError: error,
    reps: [
      for (final (i, v) in velocities.indexed)
        RepRecord(
          index: i + 1,
          startSec: i * 2.0,
          endSec: i * 2.0 + 0.8,
          meanVelocity: v,
          peakVelocity: v * 1.6,
        ),
    ],
  );
}

final _today = DateTime.utc(2026, 10, 12, 9);

Session _session(String id, int daysAgo, List<SetRecord> sets,
        {String exercise = 'squat_low_bar'}) =>
    Session(
      id: id,
      exerciseId: exercise,
      startedAt: _today.subtract(Duration(days: daysAgo)),
      sets: sets,
    );

void main() {
  group('setTypesCompatible', () {
    test('warm-up group, back-off, untagged', () {
      expect(setTypesCompatible(SetType.warmUp, SetType.topSet), isTrue);
      expect(setTypesCompatible(SetType.topSet, SetType.lastWarmUp), isTrue);
      expect(setTypesCompatible(SetType.backoff, SetType.backoff), isTrue);
      expect(setTypesCompatible(SetType.backoff, SetType.topSet), isFalse);
      expect(setTypesCompatible(SetType.topSet, SetType.backoff), isFalse);
      expect(setTypesCompatible(null, null), isTrue);
      expect(setTypesCompatible(null, SetType.topSet), isFalse);
      expect(setTypesCompatible(SetType.topSet, null), isFalse);
    });
  });

  group('buildReadiness', () {
    final todaySet = _set(100, [0.60, 0.55], type: SetType.topSet);
    final current = _session('now', 0, [todaySet]);

    test('first matching set per earlier session, newest first', () {
      final r = buildReadiness([
        current,
        _session('a', 2, [
          _set(100, [0.4], type: SetType.backoff), // incompatible type
          _set(100, [0.50, 0.52], type: SetType.warmUp), // first match
          _set(100, [0.9], type: SetType.topSet),
        ]),
        _session('b', 9, [_set(100, [0.58], type: SetType.topSet)]),
        _session('c', 5, [
          _set(100, [0.7], unit: WeightUnit.lb, type: SetType.topSet),
          _set(100, [0.7], error: 'bad', type: SetType.topSet),
          _set(105, [0.7], type: SetType.topSet),
        ]), // nothing matches
        _session('old', 91, [_set(100, [0.3], type: SetType.topSet)]),
        _session('bench', 1, [_set(100, [0.3], type: SetType.topSet)],
            exercise: 'bench_press'),
        _session('later', -1, [_set(100, [0.3], type: SetType.topSet)]),
      ], current: current, set: todaySet);

      expect(r.lastSessionSpeed, 0.52);
      expect(r.historicAverage, closeTo(0.55, 1e-12));
      expect(r.points.map((p) => p.speed), [0.52, 0.58]);
    });

    test('one earlier session: last only, no average or history', () {
      final r = buildReadiness([
        current,
        _session('a', 3, [_set(100, [0.5], type: SetType.topSet)]),
      ], current: current, set: todaySet);
      expect(r.lastSessionSpeed, 0.5);
      expect(r.historicAverage, isNull);
      expect(r.points, isEmpty);
    });

    test('keeps the newest 12 sessions', () {
      final r = buildReadiness([
        for (var d = 1; d <= 15; d++)
          _session('s$d', d, [_set(100, [d / 100], type: SetType.topSet)]),
      ], current: current, set: todaySet);
      expect(r.points, hasLength(readinessMaxResults));
      expect(r.points.first.speed, 0.01);
      expect(r.points.last.speed, 0.12);
    });

    test('no weight or no matches gives empty', () {
      expect(
          buildReadiness([current], current: current, set: _set(0, [0.5]))
              .hasHistory,
          isFalse);
      expect(buildReadiness([current], current: current, set: todaySet),
          same(ReadinessResult.empty));
    });
  });

  group('compareReadiness', () {
    ReadinessComparison? cmp(double cur, double? last, double? avg,
            {SetType? type = SetType.topSet}) =>
        compareReadiness(
          current: cur,
          lastSession: last,
          average: avg,
          setType: type,
          weightLabel: '100 kg',
        );

    test('faster than both', () {
      final c = cmp(0.70, 0.60, 0.62)!;
      expect(c.title, 'Faster');
      expect(c.isFaster, isTrue);
      expect(c.description,
          '100 kg moved faster than Last Session and Historical Average.');
    });

    test('slower than last only', () {
      final c = cmp(0.50, 0.60, 0.52)!;
      expect(c.description, '100 kg moved slower than Last Session.');
      expect(c.isFaster, isFalse);
    });

    test('5 % relative threshold applies below 0.05 m/s', () {
      // 0.03 m/s is 10 % of 0.30.
      expect(cmp(0.33, 0.30, null)?.title, 'Faster');
      // 0.01 m/s is 1 % of 1.00.
      expect(cmp(1.01, 1.00, null), isNull);
    });

    test('disagreeing directions give no verdict', () {
      // Slower than last, faster than average: the average is skipped
      // because last was added in the other direction.
      final c = cmp(0.60, 0.70, 0.50)!;
      expect(c.description, '100 kg moved slower than Last Session.');
    });

    test('warm-up and back-off sets get no verdict', () {
      expect(cmp(0.9, 0.6, 0.6, type: SetType.warmUp), isNull);
      expect(cmp(0.9, 0.6, 0.6, type: SetType.backoff), isNull);
      expect(cmp(0.9, 0.6, 0.6, type: SetType.lastWarmUp), isNotNull);
      expect(cmp(0.9, 0.6, 0.6, type: null), isNotNull);
    });

    test('nothing to compare', () {
      expect(cmp(0.6, null, null), isNull);
      expect(cmp(0, 0.5, 0.5), isNull);
    });
  });

  test('daysAgoText', () {
    final now = DateTime(2026, 10, 12, 9);
    String ago(int d) => daysAgoText(now.subtract(Duration(days: d)), now);
    expect(ago(0), 'Today');
    expect(ago(1), 'Yesterday');
    expect(ago(6), '6 days ago');
    expect(ago(7), '1 week ago');
    expect(ago(20), '2 weeks ago');
    expect(ago(45), '1 month ago');
    expect(ago(75), '2 months ago');
  });

  testWidgets('card shows numbers, verdict and history', (tester) async {
    final set = _set(100, [0.70, 0.66], type: SetType.topSet);
    final result = buildReadiness([
      _session('a', 1, [_set(100, [0.60], type: SetType.topSet)]),
      _session('b', 8, [_set(100, [0.62], type: SetType.topSet)]),
    ], current: _session('now', 0, [set]), set: set);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReadinessCard(result: result, set: set, now: _today),
        ),
      ),
    ));
    String text(String key) =>
        tester.widget<Text>(find.byKey(Key(key))).data!;
    expect(text('readinessThis'), '0.70');
    expect(text('readinessLast'), '0.60');
    expect(text('readinessAvg'), '0.61');
    expect(find.textContaining('moved faster than Last Session'),
        findsOneWidget);
    expect(find.byType(ReadinessStrip), findsOneWidget);

    expect(find.textContaining('Yesterday'), findsNothing);
    await tester.tap(find.text('See More'));
    await tester.pump();
    expect(find.textContaining('Yesterday'), findsOneWidget);
    expect(find.textContaining('1 week ago'), findsOneWidget);
  });

  testWidgets('card without history', (tester) async {
    final set = _set(100, [0.7]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReadinessCard(result: ReadinessResult.empty, set: set),
      ),
    ));
    expect(find.text('No historical data available'), findsOneWidget);
    expect(find.byType(ReadinessStrip), findsNothing);
    expect(find.text('See More'), findsNothing);
  });
}
