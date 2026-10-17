import 'package:barbell_app/ui/charts/rpe_profile_chart.dart';
import 'package:barbell_app/ui/feedback_sheets.dart';
import 'package:barbell_app/workout/rpe_profile.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _ids = 0;

SetRecord _set(double? rpe, List<double> velocities,
    {double weight = 100, String? error, DateTime? at}) {
  final t = at ?? DateTime.utc(2026, 10, 12, 9);
  return SetRecord(
    id: 'set${_ids++}',
    startedAt: t,
    endedAt: t.add(const Duration(seconds: 20)),
    weight: weight,
    unit: WeightUnit.kg,
    rpe: rpe,
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

Session _session(List<SetRecord> sets,
        {String id = 's', String exercise = 'squat_low_bar'}) =>
    Session(
      id: id,
      exerciseId: exercise,
      startedAt: DateTime.utc(2026, 10, 12, 9),
      sets: sets,
    );

void main() {
  group('quartiles', () {
    test('percentile interpolates linearly', () {
      expect(percentile([1, 2, 3, 4], 0.25), closeTo(1.75, 1e-12));
      expect(percentile([1, 2, 3, 4], 0.75), closeTo(3.25, 1e-12));
      expect(percentile([5], 0.5), 5);
    });

    test('IQR, with a 0.02 band when it collapses', () {
      expect(velocityRangeFromQuartiles([]), isNull);
      expect(velocityRangeFromQuartiles([0.5]), (0.5, 0.52));
      final (lo, hi) = velocityRangeFromQuartiles([0.4, 0.4, 0.4])!;
      expect(lo, closeTo(0.4, 1e-12));
      expect(hi, closeTo(0.42, 1e-12));
      final (q1, q3) = velocityRangeFromQuartiles([0.6, 0.3, 0.5, 0.4])!;
      expect(q1, closeTo(0.375, 1e-12));
      expect(q3, closeTo(0.525, 1e-12));
    });
  });

  group('buildRpeProfile', () {
    final sessions = [
      _session([
        _set(7, [0.8, 0.70]),
        _set(7, [0.8, 0.72]),
        _set(8, [0.6, 0.55]),
        _set(8, [0.6, 0.50]),
        _set(9, [0.4, 0.35]),
        _set(null, [0.9, 0.8]), // untagged
        _set(9, [], error: 'bad'), // failed analysis
        _set(10, []), // no reps
        _set(10, [0.3, 0.0]), // last rep velocity missing
      ]),
      _session([_set(6, [1.0])], id: 'b', exercise: 'bench_press'),
    ];

    test('groups last-rep speeds by RPE, sorted', () {
      final p = buildRpeProfile(sessions, exerciseId: 'squat_low_bar');
      expect(p.points.map((e) => e.rpe), [7, 8, 9]);
      final seven = p.points.first;
      expect(seven.velocities, [0.70, 0.72]);
      expect(seven.minVelocity, closeTo(0.705, 1e-12));
      expect(seven.maxVelocity, closeTo(0.715, 1e-12));
      expect(seven.absoluteMin, 0.70);
      expect(seven.absoluteMax, 0.72);
    });

    test('defaults without a speed', () {
      final p = buildRpeProfile(sessions, exerciseId: 'squat_low_bar');
      expect((p.minRpe, p.maxRpe), (7.0, 9.0));
      expect((p.minSpeed, p.maxSpeed), (0.0, 1.0));
      expect(p.hasSuggestion, isFalse);
    });

    test('window is ±20 % of the speed; RPE range from overlapping IQRs', () {
      // 0.6 → 0.48–0.72: overlaps RPE 7 (0.705–0.715) and 8 (0.5125–0.5375).
      final p = buildRpeProfile(sessions,
          exerciseId: 'squat_low_bar', speed: 0.6);
      expect(p.minSpeed, closeTo(0.48, 1e-12));
      expect(p.maxSpeed, closeTo(0.72, 1e-12));
      expect((p.minRpe, p.maxRpe), (7.0, 8.0));
      expect(p.hasSuggestion, isTrue);

      final slow = buildRpeProfile(sessions,
          exerciseId: 'squat_low_bar', speed: 0.35);
      expect((slow.minRpe, slow.maxRpe), (9.0, 9.0));
    });

    test('no overlap falls back to 7–9', () {
      final p = buildRpeProfile(sessions,
          exerciseId: 'squat_low_bar', speed: 1.5);
      expect((p.minRpe, p.maxRpe), (7.0, 9.0));
      expect(p.hasSuggestion, isFalse);
    });
  });

  test('buildRpeGroups keeps tagged sets, sorts rows descending', () {
    final sessions = [
      _session([
        _set(8, [0.6, 0.5], weight: 100, at: DateTime.utc(2026, 10, 1)),
        _set(8, [0.6, 0.4], weight: 120, at: DateTime.utc(2026, 10, 3)),
        _set(8, [], weight: 110, at: DateTime.utc(2026, 10, 2)),
        _set(7, [0.7], weight: 90, at: DateTime.utc(2026, 10, 1)),
        _set(null, [0.7]),
        _set(9, [0.3], error: 'bad'),
      ]),
    ];
    List<double> weights(RpeProfileSort sort) => buildRpeGroups(sessions,
            exerciseId: 'squat_low_bar', sort: sort)
        .last
        .rows
        .map((r) => r.weight)
        .toList();

    final groups = buildRpeGroups(sessions, exerciseId: 'squat_low_bar');
    expect(groups.map((g) => g.rpe), [7, 8]);
    expect(groups.first.rows.single.sessionId, 's');
    expect(weights(RpeProfileSort.date), [120, 110, 100]);
    expect(weights(RpeProfileSort.speed), [100, 120, 110]); // null speed last
    expect(weights(RpeProfileSort.weight), [120, 110, 100]);
  });

  test('copyWith can clear the RPE', () {
    final s = _set(8, [0.5]);
    expect(s.copyWith().rpe, 8);
    expect(s.copyWith(rpe: 9).rpe, 9);
    expect(s.copyWith(clearRpe: true).rpe, isNull);
  });

  test('rpeColor covers half steps 5–10 only', () {
    expect(rpeColor(5), const Color(0xff736984));
    expect(rpeColor(10), const Color(0xffe85252));
    expect(rpeColor(7.25), isNull);
    expect(rpeColor(4.5), isNull);
  });

  testWidgets('RPE sheet shows the suggested RPE range and profile',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final profile = buildRpeProfile([
      _session([
        _set(7, [0.7]),
        _set(8, [0.55]),
      ]),
    ], exerciseId: 'squat_low_bar', speed: 0.6);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              showRpeSheet(context, set: _set(null, [0.6]), profile: profile),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rpeSuggestion')), findsOneWidget);
    expect(find.text('Past sets with a last rep near 0.60 m/s: RPE 7–8'),
        findsOneWidget);
    expect(find.byType(RpeProfileChart), findsOneWidget);
    // No RPE yet: nothing to clear.
    expect(find.byKey(const Key('rpeClear')), findsNothing);

    await tester.tap(find.byKey(const Key('rpeChartZoom')));
    await tester.pump();
    expect(find.byTooltip('Zoom in'), findsOneWidget);
  });

  testWidgets('empty profile says so', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RpeProfileChart(
          profile: buildRpeProfile(const [], exerciseId: 'x', speed: 0.5),
        ),
      ),
    ));
    expect(find.text('No data to display'), findsOneWidget);
  });
}
