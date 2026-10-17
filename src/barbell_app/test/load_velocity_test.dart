import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/ui/charts/load_velocity_chart.dart';
import 'package:barbell_app/workout/load_velocity.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RepRecord _rep(int i, double mean) => RepRecord(
      index: i,
      startSec: i * 2.0,
      endSec: i * 2.0 + 0.8,
      meanVelocity: mean,
      peakVelocity: mean * 1.6,
    );

SetRecord _set(
  String id,
  double weight,
  List<double> velocities, {
  WeightUnit unit = WeightUnit.kg,
  SetType? type,
  String? error,
  DateTime? at,
}) {
  final t = at ?? DateTime.utc(2026, 10, 12, 9);
  return SetRecord(
    id: id,
    startedAt: t,
    endedAt: t.add(const Duration(seconds: 20)),
    weight: weight,
    unit: unit,
    setType: type,
    analysisError: error,
    reps: [for (final (i, v) in velocities.indexed) _rep(i + 1, v)],
  );
}

Session _session(String id, List<SetRecord> sets,
        {String exercise = 'squat_low_bar', DateTime? at}) =>
    Session(
      id: id,
      exerciseId: exercise,
      startedAt: at ?? DateTime.utc(2026, 10, 12, 9),
      sets: sets,
    );

void main() {
  group('buildLoadVelocity', () {
    final session = _session('s', [
      _set('a', 60, [1.0, 1.1, 0.9]),
      _set('b', 100, [0.6, 0.5]),
      _set('c', 120, [0.4], type: SetType.backoff),
      _set('d', 110, [0.5], error: 'no reps'),
      _set('e', 0, [0.8]),
      _set('f', 90, []),
      _set('g', 220.46226218, [0.7], unit: WeightUnit.lb),
    ]);

    test('fastest rep per set, filtered like Stance', () {
      final d = buildLoadVelocity(session, unit: WeightUnit.kg);
      expect(d.points.map((p) => p.setIndex), [0, 1, 6]);
      expect(d.points[0].velocity, 1.1);
      expect(d.points[1].velocity, 0.6);
      expect(d.points[2].weight, closeTo(100, 1e-9));
      expect(d.comparisonPoints, isEmpty);
    });

    test('last rep choice', () {
      final d = buildLoadVelocity(session,
          unit: WeightUnit.kg, choice: SpeedChoice.last);
      expect(d.points.map((p) => p.velocity), [0.9, 0.5, 0.7]);
    });

    test('plots in the requested unit', () {
      final d = buildLoadVelocity(session, unit: WeightUnit.lb);
      expect(d.points[0].weight, closeTo(60 * lbPerKg, 1e-9));
      expect(d.points[2].weight, closeTo(220.46226218, 1e-9));
    });

    test('bounds pad both series by 10 %', () {
      final d = buildLoadVelocity(
        _session('s', [_set('a', 100, [0.5])]),
        unit: WeightUnit.kg,
        comparison: _session('c', [_set('x', 50, [1.0])]),
      );
      expect(d.comparisonPoints.single.weight, 50);
      expect(d.bounds.minWeight, closeTo(45, 1e-9));
      expect(d.bounds.maxWeight, closeTo(110, 1e-9));
      expect(d.bounds.minVelocity, closeTo(0.45, 1e-9));
      expect(d.bounds.maxVelocity, closeTo(1.1, 1e-9));
    });

    test('empty session gives empty data', () {
      final d = buildLoadVelocity(_session('s', []), unit: WeightUnit.kg);
      expect(d.isEmpty, isTrue);
      expect(d.bounds, same(LoadVelocityBounds.empty));
    });
  });

  group('buildWeightHistory', () {
    DateTime day(int d) => DateTime.utc(2026, 9, d, 9);

    test('exact weight and unit, same exercise, oldest first', () {
      final sessions = [
        _session('s2', [
          _set('b', 100, [0.5, 0.6], at: day(5)),
          _set('c', 100, [0.4], unit: WeightUnit.lb, at: day(5)),
          _set('d', 100.5, [0.4], at: day(5)),
          _set('e', 100, [0.3], error: 'bad', at: day(5)),
          _set('f', 100, [0.45], type: SetType.backoff, at: day(6)),
        ]),
        _session('s1', [_set('a', 100, [0.7, 0.8], at: day(1))]),
        _session('bench', [_set('z', 100, [0.2], at: day(2))],
            exercise: 'bench_press'),
      ];
      final h = buildWeightHistory(sessions,
          exerciseId: 'squat_low_bar', weight: 100, unit: WeightUnit.kg);
      expect(h.map((p) => p.date), [day(1), day(5), day(6)]);
      expect(h[0].minVelocity, 0.7);
      expect(h[0].maxVelocity, 0.8);
      // Back-off sets count; one-rep sets get the 0.1 bump.
      expect(h[2].minVelocity, 0.45);
      expect(h[2].maxVelocity, closeTo(0.55, 1e-12));
    });

    test('keeps the last 12', () {
      final sets = [
        for (var d = 1; d <= 15; d++) _set('s$d', 80, [0.5, 0.6], at: day(d)),
      ];
      final h = buildWeightHistory([_session('s', sets)],
          exerciseId: 'squat_low_bar', weight: 80, unit: WeightUnit.kg);
      expect(h, hasLength(weightHistoryMaxPoints));
      expect(h.first.date, day(4));
      expect(h.last.date, day(15));
    });
  });

  test('niceTicks steps by 1/2/5 × 10ⁿ', () {
    final unit = niceTicks(0, 1, 5);
    expect(unit, hasLength(6));
    for (final (i, t) in unit.indexed) {
      expect(t, closeTo(i * 0.2, 1e-9));
    }
    // Step 20; 40 is below the minimum, 120 is within half a step of 110.
    expect(niceTicks(45, 110, 5), [60, 80, 100, 120]);
  });

  testWidgets('tapping near a point selects its set', (tester) async {
    final data = buildLoadVelocity(
      _session('s', [
        _set('a', 60, [1.0]),
        _set('b', 100, [0.5]),
      ]),
      unit: WeightUnit.kg,
    );
    int? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: LoadVelocityChart(
            data: data,
            weightLabel: 'Weight (kg)',
            onSelect: (i) => selected = i,
          ),
        ),
      ),
    ));
    final chart = find.byType(LoadVelocityChart);
    final origin = tester.getTopLeft(chart);
    final size = tester.getSize(chart);
    // Bounds: weight 54–110, velocity 0.45–1.1; plot insets 48/16/16/36.
    final plotW = size.width - 48 - 16, plotH = size.height - 16 - 36;
    Offset at(double w, double v) =>
        origin +
        Offset(48 + (w - 54) / 56 * plotW,
            16 + plotH - (v - 0.45) / 0.65 * plotH);

    await tester.tapAt(at(100, 0.5) + const Offset(5, 5));
    expect(selected, 1);
    await tester.tapAt(at(60, 1.0));
    expect(selected, 0);
    selected = null;
    await tester.tapAt(at(80, 0.75)); // far from both points
    expect(selected, isNull);
  });
}
