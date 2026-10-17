import 'dart:io';

import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/recording/recording.dart';
import 'package:barbell_app/ui/app_scope.dart';
import 'package:barbell_app/ui/charts/load_velocity_chart.dart';
import 'package:barbell_app/ui/charts/rep_velocity_chart.dart';
import 'package:barbell_app/ui/comparison_views.dart';
import 'package:barbell_app/ui/session_feedback_page.dart';
import 'package:barbell_app/workout/load_velocity.dart';
import 'package:barbell_app/workout/sensor_controller.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:barbell_app/workout/session_comparison.dart';
import 'package:barbell_app/workout/session_store.dart';
import 'package:barbell_app/workout/session_tags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _ids = 0;

SetRecord _set(double weight, List<double> velocities,
    {SetType? type, double? rpe, DateTime? at}) {
  final t = at ?? DateTime(2026, 10, 12, 9);
  return SetRecord(
    id: 'set${_ids++}',
    startedAt: t,
    endedAt: t,
    weight: weight,
    unit: WeightUnit.kg,
    setType: type,
    rpe: rpe,
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

/// Sessions default to the Primary day type: untagged ones get no
/// comparison sessions at all.
Session _session(String id, DateTime at, List<SetRecord> sets,
        {String exercise = 'squat_low_bar',
        SessionDayType? day = SessionDayType.primary}) =>
    Session(
        id: id,
        exerciseId: exercise,
        startedAt: at,
        sets: sets,
        tags: day == null ? const [] : [day.wireTag]);

void main() {
  test('comparisonCandidates: earlier, same exercise, one per day', () {
    final now = _session('now', DateTime(2026, 10, 12, 18), []);
    final c = comparisonCandidates([
      now,
      _session('d10-late', DateTime(2026, 10, 10, 19), []),
      _session('d10-early', DateTime(2026, 10, 10, 7), []),
      _session('d11', DateTime(2026, 10, 11, 12), []),
      _session('today-earlier', DateTime(2026, 10, 12, 8), []),
      _session('future', DateTime(2026, 10, 13, 8), []),
      _session('bench', DateTime(2026, 10, 11, 9), [],
          exercise: 'bench_press'),
    ], now);
    expect(c.map((s) => s.id), ['today-earlier', 'd11', 'd10-early']);
  });

  test('comparisonCandidates: same day type only; none when untagged', () {
    final at = DateTime(2026, 10, 12, 18);
    final others = [
      _session('primary', DateTime(2026, 10, 10), []),
      _session('secondary', DateTime(2026, 10, 9), [], day: SessionDayType.secondary),
      _session('untagged', DateTime(2026, 10, 8), [], day: null),
    ];
    expect(comparisonCandidates(others, _session('now', at, [])).map((s) => s.id),
        ['primary']);
    expect(
        comparisonCandidates(
                others, _session('now', at, [], day: SessionDayType.secondary))
            .map((s) => s.id),
        ['secondary']);
    expect(comparisonCandidates(others, _session('now', at, [], day: null)), isEmpty);
  });

  test('comparisonTable rows', () {
    final s = _session('s', DateTime(2026, 10, 12), [
      _set(100, [0.6, 0.5], type: SetType.topSet, rpe: 8.5),
      _set(60, []),
    ]);
    final fastest = comparisonTable(s, SpeedChoice.fastest);
    expect(fastest.first.type, 'TS');
    expect(fastest.first.reps, 2);
    expect(fastest.first.speed, '0.60');
    expect(fastest.first.rpe, '8.5');
    expect(fastest.last.type, '--');
    expect(fastest.last.speed, '0.00');
    expect(fastest.last.rpe, '-');
    expect(comparisonTable(s, SpeedChoice.last).first.speed, '0.50');
  });

  test('rep bounds and compare options', () {
    final (lo, hi) = repSpeedBounds([
      _set(100, [0.5, 0.0]),
      _set(100, [1.0]),
    ]);
    expect(lo, closeTo(0.45, 1e-12));
    expect(hi, closeTo(1.1, 1e-12));
    expect(repSpeedBounds([_set(100, [])]), (0.0, 1.0));

    final (clo, chi) = repChartBounds([0.5, 0.8]);
    expect(clo, closeTo(0.45, 1e-12));
    expect(chi, closeTo(0.88, 1e-12));

    final s = _session('s', DateTime(2026), [
      for (var i = 0; i < 4; i++) _set(100, [0.5]),
    ]);
    expect(compareSetOptions(s, 1), [3, 2, 0]);
  });

  test('catmullRomPath passes through every point', () {
    final pts = [const Offset(0, 0), const Offset(10, 5), const Offset(20, 0)];
    final b = catmullRomPath(pts).getBounds();
    expect(b.left, 0);
    expect(b.right, 20);
    expect(b.bottom, greaterThanOrEqualTo(5));
  });

  group('session page', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cmp_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    testWidgets('defaults to the newest earlier session; table and reps views',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final store = SessionStore(baseDirectory: () async => dir);
      final current = _session('now', DateTime(2026, 10, 12, 9), [
        _set(100, [0.60, 0.55], type: SetType.topSet),
        _set(120, [0.45, 0.40], type: SetType.topSet),
      ]);
      final older = _session('older', DateTime(2026, 10, 1, 9), [
        _set(100, [0.50], type: SetType.topSet),
      ]);
      final newer = _session('newer', DateTime(2026, 10, 8, 9), [
        _set(100, [0.58], type: SetType.topSet),
        _set(120, [0.42], type: SetType.topSet),
      ]);
      await tester.runAsync(() async {
        for (final s in [current, older, newer]) {
          await store.save(s);
        }
      });

      await tester.pumpWidget(AppScope(
        sensor: SensorController(),
        sessions: store,
        recordings: RecordingStore(baseDirectory: () async => dir),
        child: MaterialApp(home: SessionFeedbackPage(session: current)),
      ));
      // Let the async session list load (real file I/O).
      for (var i = 0;
          i < 50 && find.byKey(const Key('comparisonPicker')).evaluate().isEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }

      final picker = tester.widget<StanceMenuPicker<String?>>(
          find.byKey(const Key('comparisonPicker')));
      expect(picker.value, 'newer');
      final chart = tester.widget<LoadVelocityChart>(
          find.byType(LoadVelocityChart));
      expect(chart.data.comparisonPoints, hasLength(2));

      await tester.tap(find.text('Table'));
      await tester.pump();
      expect(find.textContaining('This Session · '), findsOneWidget);
      expect(find.textContaining('Comparison Session · Thu 8 Oct 2026'),
          findsOneWidget);
      expect(find.text('0.58'), findsOneWidget);

      await tester.tap(find.text('Reps').first); // the view button
      await tester.pump();
      // Two sets in the reps row.
      expect(
          find.descendant(
              of: find.byType(RepSpeedRow),
              matching: find.byType(RepVelocityChart)),
          findsNWidgets(2));
    });
  });
}
