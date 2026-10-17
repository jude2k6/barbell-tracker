import 'package:barbell_app/video/set_video_export_rules.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:flutter_test/flutter_test.dart';

SetVideoExportPlan plan3() => buildExportPlan(
      repWindowsSec: const [(12, 13), (15, 16), (18, 19)],
      repMeanVelocitiesMps: const [0.6, 0.5, 0.4],
      videoDurationMs: 60000,
    )!;

void main() {
  group('buildExportPlan', () {
    test('crops 10 s before the first rep to 10 s after the last', () {
      final p = plan3();
      expect(p.cropStartMs, 2000);
      expect(p.cropEndMs, 29000);
      expect(p.repWindows.map((r) => (r.number, r.startMs, r.endMs)),
          [(1, 10000, 11000), (2, 13000, 14000), (3, 16000, 17000)]);
    });

    test('clamps the crop to the video', () {
      final p = buildExportPlan(
        repWindowsSec: const [(3, 4), (6, 7.5)],
        repMeanVelocitiesMps: const [0.6, 0.5],
        videoDurationMs: 12000,
      )!;
      expect(p.cropStartMs, 0);
      expect(p.cropEndMs, 12000);
      expect(p.repWindows.first.startMs, 3000);
    });

    test('uses the earliest start and latest end, not the first and last rep', () {
      final p = buildExportPlan(
        repWindowsSec: const [(20, 25), (15, 16)],
        repMeanVelocitiesMps: const [],
        videoDurationMs: 100000,
      )!;
      expect((p.cropStartMs, p.cropEndMs), (5000, 35000));
    });

    test('no reps, no duration or an empty crop: no export', () {
      expect(
          buildExportPlan(
              repWindowsSec: const [], repMeanVelocitiesMps: const [], videoDurationMs: 1000),
          isNull);
      expect(
          buildExportPlan(
              repWindowsSec: const [(1, 2)], repMeanVelocitiesMps: const [], videoDurationMs: 0),
          isNull);
    });

    test('reps outside the video still give a window clamped at 0', () {
      final p = buildExportPlan(
        repWindowsSec: const [(-3, -2), (1, 2)],
        repMeanVelocitiesMps: const [0.5, 0.5],
        videoDurationMs: 5000,
      )!;
      expect((p.cropStartMs, p.cropEndMs), (0, 5000));
      expect((p.repWindows[0].startMs, p.repWindows[0].endMs), (0, 0));
    });

    test('missing or non-positive velocity is null', () {
      final p = buildExportPlan(
        repWindowsSec: const [(1, 2), (3, 4), (5, 6)],
        repMeanVelocitiesMps: const [0.5, 0],
        videoDurationMs: 30000,
      )!;
      expect(p.repWindows.map((r) => r.meanVelocityMps), [0.5, null, null]);
    });

    test('sticking bands become fractions', () {
      final p = buildExportPlan(
        repWindowsSec: const [(1, 2), (3, 4)],
        repMeanVelocitiesMps: const [0.5, 0.5],
        videoDurationMs: 30000,
        repStickingBandsPct: const [(20, 150), null],
      )!;
      expect(p.repWindows[0].stickingBand, (0.2, 1.0));
      expect(p.repWindows[1].stickingBand, isNull);
    });
  });

  test('stickingBandFraction rejects empty and inverted bands', () {
    expect(stickingBandFraction((10, 0)), isNull);
    expect(stickingBandFraction((60, 40)), isNull);
    expect(stickingBandFraction((-10, 40)), (0.0, 0.4));
  });

  group('overlay timing', () {
    test('bar eases in over the rep, holds 200 ms, empties over 300 ms', () {
      final p = plan3();
      expect(barFillState(p, 9999), (0.0, -1));
      expect(barFillState(p, 10000), (0.0, 0));
      expect(barFillState(p, 10500), (0.5, 0));
      expect(barFillState(p, 10250).$1, closeTo(0.15625, 1e-9));
      expect(barFillState(p, 11000), (1.0, 0));
      expect(barFillState(p, 11200), (1.0, 0));
      expect(barFillState(p, 11350), (0.5, 0));
      expect(barFillState(p, 11500), (0.0, 0));
      expect(barFillState(p, 11501), (0.0, -1));
    });

    test('the bar stays full after the last rep', () {
      expect(barFillState(plan3(), 25000), (1.0, 2));
    });

    test('rep number and velocity only show inside a rep', () {
      final p = plan3();
      expect(activeRepIndex(p, 9999), -1);
      expect(activeRepIndex(p, 10000), 0);
      expect(activeRepIndex(p, 11000), 0);
      expect(activeRepIndex(p, 11100), -1);
      expect(activeRepIndex(p, 16500), 2);
    });

    test('samples cover the whole clip', () {
      final s = OverlaySamples.of(plan3(), stepMs: 100);
      expect(s.fill.length, 271);
      expect(s.barRep[105], 0);
      expect(s.fill[105], closeTo(0.5, 1e-6));
      expect(s.activeRep[115], -1);
      expect(s.barRep[116], -1);
      expect(s.barRep[270], 2);
    });

    test('panel texts', () {
      expect(overlayWeightLine('140 kg', 5), '140 kg x 5');
      expect(overlayVelocityText(0.456), '0.46');
      expect(overlayVelocityText(null), '0.00');
    });
  });

  group('input and output', () {
    final set = SetRecord(
      id: 's1',
      startedAt: DateTime.utc(2026, 10, 12, 10),
      endedAt: DateTime.utc(2026, 10, 12, 10, 1),
      weight: 140,
      unit: WeightUnit.kg,
      reps: const [
        RepRecord(
            index: 1,
            startSec: 3,
            endSec: 4,
            meanVelocity: 0.6,
            peakVelocity: 1,
            sticking: StickingRecord(startPct: 30, endPct: 60)),
        RepRecord(index: 2, startSec: 6, endSec: 7, meanVelocity: 0.5, peakVelocity: 1),
      ],
      videoFile: 'videos/s1.mp4',
      videoOffsetSec: 1.5,
    );

    test('fromSet moves reps onto video time', () {
      final i = SetVideoOverlayInput.fromSet(set,
          videoPath: '/v/s1.mp4', weightLabel: '140 kg');
      expect(i.repsCount, 2);
      expect(i.repWindowsSec, [(4.5, 5.5), (7.5, 8.5)]);
      expect(i.repMeanVelocitiesMps, [0.6, 0.5]);
      expect(i.repStickingBandsPct, [(30.0, 60.0), null]);
    });

    test('file name and signature', () {
      expect(exportBaseName('s1'), 'overlay_set_s1_4k');
      expect(exportBaseName('s1', maxShortSidePx: 1080), 'overlay_set_s1');
      final a = SetVideoOverlayInput.fromSet(set,
          videoPath: '/v/s1.mp4', weightLabel: '140 kg');
      final b = SetVideoOverlayInput.fromSet(set.copyWith(videoOffsetSec: 1.6),
          videoPath: '/v/s1.mp4', weightLabel: '140 kg');
      expect(exportSignature(a), exportSignature(a));
      expect(exportSignature(a), endsWith('@full'));
      expect(exportSignature(a), isNot(exportSignature(b)));
    });

    test('signature hash is Java/Kotlin String.hashCode', () {
      expect(javaStringHash('hello'), 99162322);
      expect(javaStringHash('polygenelubricants'), -2147483648);
      expect(javaStringHash(''), 0);
    });
  });

  test('disk cap deletes oldest exports with their signatures', () {
    const files = [
      SizedFile('overlay_set_a_4k.mp4', 1, 300),
      SizedFile('overlay_set_a_4k.sig', 5, 10),
      SizedFile('overlay_set_b_4k.mp4', 2, 300),
      SizedFile('overlay_set_b_4k.sig', 2, 10),
      SizedFile('overlay_set_c_4k.mp4', 3, 300),
    ];
    expect(namesToDeleteToEnforceCap(files, 1000), isEmpty);
    expect(namesToDeleteToEnforceCap(files, 610),
        {'overlay_set_a_4k.mp4', 'overlay_set_a_4k.sig'});
    expect(namesToDeleteToEnforceCap(files, 300), {
      'overlay_set_a_4k.mp4',
      'overlay_set_a_4k.sig',
      'overlay_set_b_4k.mp4',
      'overlay_set_b_4k.sig',
    });
    expect(namesToDeleteToEnforceCap(files, -1), isEmpty);
  });
}
