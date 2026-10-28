import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/workout/guide_tips.dart';
import 'package:barbell_app/workout/preferences.dart';
import 'package:barbell_app/workout/readiness.dart';
import 'package:barbell_app/workout/rep_editing.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:flutter_test/flutter_test.dart';

const _sticking = StickingRecord(startPct: 30, endPct: 60);

RepRecord _rep(int i, double start, double end, {double? rom, double mean = 0.5}) =>
    RepRecord(
      index: i,
      startSec: start,
      endSec: end,
      meanVelocity: mean,
      peakVelocity: mean * 2,
      romMeters: rom,
      sticking: i == 1 ? _sticking : null,
    );

/// 10 Hz trace, 0–4.9 s: velocity = sample index / 10.
SetRecord _set(List<RepRecord> reps, {bool trace = true, DateTime? end}) => SetRecord(
      id: 's',
      startedAt: DateTime(2026, 10, 17, 9),
      endedAt: end ?? DateTime(2026, 10, 17, 9, 1),
      weight: 100,
      unit: WeightUnit.kg,
      reps: reps,
      velocityTrace: trace ? [for (var i = 0; i < 50; i++) i / 10] : const [],
      traceHz: trace ? 10 : null,
    );

void main() {
  group('edit window', () {
    test('7 days from the set end, never negative', () {
      final s = _set(const []);
      expect(editTimeLeft(s, DateTime(2026, 10, 17, 9, 1)), const Duration(days: 7));
      expect(editTimeLeft(s, DateTime(2026, 10, 25)), Duration.zero);
    });

    test('formats the first two non-zero units', () {
      expect(formatTimeLeft(Duration.zero), 'Under 1 min');
      expect(formatTimeLeft(const Duration(seconds: 59)), 'Under 1 min');
      expect(formatTimeLeft(const Duration(minutes: 45)), '45m');
      expect(formatTimeLeft(const Duration(hours: 5, minutes: 2)), '5h 2m');
      expect(formatTimeLeft(const Duration(days: 6, hours: 23, minutes: 59)), '6d 23h');
      expect(formatTimeLeft(const Duration(days: 2, minutes: 7)), '2d 7m');
    });
  });

  group('recalculateReps (CorrectRepCountUseCase)', () {
    final reps = [
      _rep(1, 0.5, 1.0, rom: 0.50),
      _rep(2, 1.5, 2.0, rom: 0.20),
      _rep(3, 2.5, 3.0, rom: 0.55),
      _rep(4, 3.5, 4.0), // unknown ROM counts as 0
    ];

    test('drops the smallest-ROM reps and renumbers', () {
      final r = recalculateReps(_set(reps), 2) as Recalculated;
      expect(r.set.reps.map((x) => x.startSec), [0.5, 2.5]);
      expect(r.set.reps.map((x) => x.index), [1, 2]);
    });

    test('ties keep the earlier rep removed first', () {
      final tied = [
        _rep(1, 0.5, 1.0, rom: 0.3),
        _rep(2, 1.5, 2.0, rom: 0.3),
        _rep(3, 2.5, 3.0, rom: 0.6),
      ];
      final r = recalculateReps(_set(tied), 2) as Recalculated;
      expect(r.set.reps.map((x) => x.startSec), [1.5, 2.5]);
    });

    test('cannot find more (or zero) reps, or work without a trace', () {
      expect((recalculateReps(_set(reps), 4) as CanOnlyFindFewer).detected, 4);
      expect(recalculateReps(_set(reps), 5), isA<CanOnlyFindFewer>());
      expect(recalculateReps(_set(reps), 0), isA<CanOnlyFindFewer>());
      expect(recalculateReps(_set(reps, trace: false), 2), isA<NoTrace>());
    });
  });

  group('validateAddTime', () {
    const markers = [RepMarker(1, 2), RepMarker(3, 4)];

    test('start may not fall inside a rep', () {
      expect(validateAddTime(markers, 1.5, isStart: true),
          (AddTimeError.startInside, 1));
      expect(validateAddTime(markers, 2.5, isStart: true), isNull);
      // Exactly on a boundary is allowed (strict comparison).
      expect(validateAddTime(markers, 2, isStart: true), isNull);
    });

    test('end checks: after start, not inside, not encompassing', () {
      expect(validateAddTime(markers, 2.2, isStart: false, start: 2.5),
          (AddTimeError.endBeforeStart, 0));
      expect(validateAddTime(markers, 3.5, isStart: false, start: 2.5),
          (AddTimeError.endInside, 2));
      expect(validateAddTime(markers, 4.5, isStart: false, start: 2.5),
          (AddTimeError.encompass, 2));
      expect(validateAddTime(markers, 2.8, isStart: false, start: 2.5), isNull);
      expect(addTimeErrorText((AddTimeError.encompass, 2)),
          'New rep cannot encompass Rep 2');
    });
  });

  group('moveMarker (RepCheckSheet drag)', () {
    const ms = [RepMarker(1.0, 2.0), RepMarker(3.0, 4.0)];

    test('a start stays after the previous end and 0.1 s before its end', () {
      expect(moveMarker(ms, 1, isStart: true, t: 2.5, durationSec: 4.9)[1],
          const RepMarker(2.5, 4.0));
      expect(moveMarker(ms, 1, isStart: true, t: 0.5, durationSec: 4.9)[1],
          const RepMarker(2.0, 4.0));
      expect(moveMarker(ms, 1, isStart: true, t: 4.5, durationSec: 4.9)[1].startSec,
          closeTo(3.9, 1e-9));
      expect(moveMarker(ms, 0, isStart: true, t: -1, durationSec: 4.9)[0],
          const RepMarker(0.0, 2.0));
    });

    test('an end stays 0.1 s after its start and before the next start', () {
      expect(moveMarker(ms, 0, isStart: false, t: 5, durationSec: 4.9)[0],
          const RepMarker(1.0, 3.0));
      expect(moveMarker(ms, 0, isStart: false, t: 0, durationSec: 4.9)[0].endSec,
          closeTo(1.1, 1e-9));
      expect(moveMarker(ms, 1, isStart: false, t: 9, durationSec: 4.9)[1],
          const RepMarker(3.0, 4.9));
      // The other marker and the input are untouched.
      final moved = moveMarker(ms, 1, isStart: false, t: 4.5, durationSec: 4.9);
      expect(moved[0], ms[0]);
      expect(ms[1], const RepMarker(3.0, 4.0));
    });
  });

  group('RepCheckRange (RepCheckSheet window and scrub)', () {
    test('short sets show the reps ± 5 s, clamped to the trace', () {
      final r = RepCheckRange(const [RepMarker(1, 2), RepMarker(3, 4)], 4.9);
      expect(r.scrolls, isFalse);
      expect(r.visible(123), (0.0, 4.9));
      expect(r.scrub(9, 0), (scrub: 4.9, windowStart: 0.0));
    });

    test('long sets show 10 s centred on the reps and pan at the edges', () {
      // Reps 6–30 s of a 40 s trace: data 1–35 s.
      final ms = [const RepMarker(6, 8), const RepMarker(28, 30)];
      final r = RepCheckRange(ms, 40);
      expect((r.dataStart, r.dataEnd), (1.0, 35.0));
      expect(r.scrolls, isTrue);
      expect(r.maxWindowStart, 25.0);
      expect(r.initialWindowStart(ms), 13.0); // mid 18 − 5
      expect(r.visible(13), (13.0, 23.0));
      // Inside, away from the edges: no pan.
      expect(r.scrub(18, 13), (scrub: 18.0, windowStart: 13.0));
      // 0.5 s from the right edge: pans right by 1 s; past it, clamped.
      expect(r.scrub(22.5, 13), (scrub: 22.5, windowStart: 14.0));
      expect(r.scrub(99, 13), (scrub: 23.0, windowStart: 14.5));
      // Left edge.
      expect(r.scrub(13.5, 13), (scrub: 13.5, windowStart: 12.0));
      // Never past the data.
      expect(r.scrub(34.9, 25).windowStart, 25.0);
      expect(r.scrub(1.2, 1).windowStart, 1.0);
    });

    test('no reps: the whole trace', () {
      final r = RepCheckRange(const [], 4.9);
      expect((r.dataStart, r.dataEnd), (0.0, 4.9));
      expect(r.initialWindowStart(const []), 0.0);
    });
  });

  group('applyRepMarkers (EditRepMarkersUseCase)', () {
    final reps = [_rep(1, 1.0, 2.0, rom: 0.5), _rep(2, 3.0, 4.0, rom: 0.6)];

    test('mean and peak from the trace; ROM and sticking only on unmoved reps',
        () {
      final s = applyRepMarkers(_set(reps), const [
        RepMarker(3.0, 4.5), // moved end
        RepMarker(1.0, 2.0), // unchanged
      ])!;
      // Sorted by start, renumbered.
      expect(s.reps.map((r) => r.index), [1, 2]);
      expect(s.reps.first.startSec, 1.0);
      // Samples 10..19 → 1.0..1.9: mean 1.45, peak 1.9.
      expect(s.reps.first.meanVelocity, closeTo(1.45, 1e-9));
      expect(s.reps.first.peakVelocity, closeTo(1.9, 1e-9));
      expect(s.reps.first.romMeters, 0.5);
      expect(s.reps.first.sticking, _sticking);
      // Samples 30..44.
      expect(s.reps.last.meanVelocity, closeTo(3.7, 1e-9));
      expect(s.reps.last.romMeters, isNull);
      expect(s.reps.last.sticking, isNull);
    });

    test('a marker reaching the trace end takes the last sample', () {
      final s = applyRepMarkers(_set(reps), const [RepMarker(4.5, 4.9)])!;
      // 4.9 s is the duration: samples 45..49.
      expect(s.reps.single.peakVelocity, closeTo(4.9, 1e-9));
    });

    test('rejects backwards markers and sets without a trace', () {
      expect(applyRepMarkers(_set(reps), const [RepMarker(2, 1)]), isNull);
      expect(applyRepMarkers(_set(reps, trace: false), const [RepMarker(1, 2)]),
          isNull);
    });
  });

  group('guide tips', () {
    final set = SetRecord(
      id: 's',
      startedAt: DateTime(2026, 10, 17),
      endedAt: DateTime(2026, 10, 17),
      weight: 100,
      unit: WeightUnit.kg,
      setType: SetType.topSet,
      reps: [_rep(1, 0, 1, mean: 0.62)],
    );
    const withHistory = ReadinessResult(
        lastSessionSpeed: 0.60, historicAverage: 0.58, points: []);

    GuideTip? tip(Set<Guide> seen, ReadinessResult r) => firstEligibleTip(
        hasSeen: seen.contains, set: set, readiness: r, weightLabel: '100 kg');

    test('in Stance order, each once', () {
      expect(tip({}, withHistory)!.message,
          "You moved 100 kg at 0.62m/s. Next time you lift 100 kg in your "
          "Primary session, you'll be able to compare.");
      final c = tip({Guide.readinessTip}, withHistory)!;
      expect(c.guide, Guide.comparisonTip);
      expect(c.message, 'You can compare This Session with last session. You moved '
          '100 kg This Session 0.02m/s faster vs. Last Session.');
      expect(tip({Guide.readinessTip, Guide.comparisonTip}, withHistory)!.guide,
          Guide.historicalAverageTip);
      expect(
          tip({Guide.readinessTip, Guide.comparisonTip, Guide.historicalAverageTip},
                  withHistory)!
              .guide,
          Guide.topSetTip);
      expect(tip(Guide.values.toSet(), withHistory), isNull);
    });

    test('comparison needs a last session; later tips need several', () {
      expect(tip({Guide.readinessTip}, ReadinessResult.empty), isNull);
      const oneSession =
          ReadinessResult(lastSessionSpeed: 0.62, historicAverage: null, points: []);
      expect(tip({Guide.readinessTip}, oneSession)!.message, contains('same speed'));
      expect(tip({Guide.readinessTip, Guide.comparisonTip}, oneSession), isNull);
    });
  });
}
