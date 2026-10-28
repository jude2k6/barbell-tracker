import 'dart:convert';
import 'dart:io';

import 'package:barbell_app/video/overlay_timeline.dart';
import 'package:barbell_app/video/video_settings.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:flutter_test/flutter_test.dart';

SetRecord videoSet({double offset = 1.5}) => SetRecord(
      id: 's1',
      startedAt: DateTime.utc(2026, 10, 12, 10),
      endedAt: DateTime.utc(2026, 10, 12, 10, 1),
      weight: 140,
      unit: WeightUnit.kg,
      reps: const [
        RepRecord(index: 1, startSec: 3, endSec: 4, meanVelocity: 0.6, peakVelocity: 1.0),
        RepRecord(index: 2, startSec: 6, endSec: 7, meanVelocity: 0.5, peakVelocity: 0.9),
      ],
      // 10 Hz trace: v = t / 10.
      velocityTrace: [for (var i = 0; i <= 100; i++) i / 100],
      traceHz: 10,
      videoFile: 'videos/s1.mp4',
      videoOffsetSec: offset,
    );

void main() {
  group('OverlayTimeline', () {
    test('a position before the video starts clamps to 0', () {
      final t = OverlayTimeline(videoSet(offset: -2));
      expect(t.clampedVideoPosition(1), Duration.zero);
      expect(t.clampedVideoPosition(3), const Duration(seconds: 1));
    });

    test('video time = sensor time + offset', () {
      final t = OverlayTimeline(videoSet());
      expect(t.sensorTime(const Duration(milliseconds: 4500)), closeTo(3.0, 1e-9));
      expect(t.videoPosition(3.0), const Duration(milliseconds: 4500));
    });

    test('tracks the active and last finished rep', () {
      final t = OverlayTimeline(videoSet(offset: 0));
      expect(t.at(const Duration(seconds: 2)).headline, isNull);
      final during = t.at(const Duration(milliseconds: 3500));
      expect(during.activeRep?.index, 1);
      expect(during.repsDone, 0);
      final between = t.at(const Duration(seconds: 5));
      expect(between.activeRep, isNull);
      expect(between.lastRep?.index, 1);
      expect(between.repsDone, 1);
      expect(t.at(const Duration(seconds: 9)).repsDone, 2);
    });

    test('interpolates velocity and returns null outside the trace', () {
      final t = OverlayTimeline(videoSet(offset: 0));
      expect(t.at(const Duration(milliseconds: 2550)).velocity, closeTo(0.255, 1e-9));
      expect(t.at(const Duration(seconds: 20)).velocity, isNull);
    });

    test('an explicit offset overrides the stored one', () {
      final t = OverlayTimeline(videoSet(offset: 1.5), offsetSec: 0.2);
      expect(t.sensorTime(const Duration(seconds: 1)), closeTo(0.8, 1e-9));
    });

    test('seek target is one second before the rep, clamped at zero', () {
      final t = OverlayTimeline(videoSet(offset: -3.5));
      expect(t.seekTarget(videoSet().reps[0]), Duration.zero);
      expect(t.seekTarget(videoSet().reps[1]), const Duration(milliseconds: 1500));
    });
  });

  group('SetRecord video fields', () {
    test('round-trip through JSON', () {
      final back = SetRecord.fromJson(
          jsonDecode(jsonEncode(videoSet().toJson())) as Map<String, dynamic>);
      expect(back.videoFile, 'videos/s1.mp4');
      expect(back.videoOffsetSec, 1.5);
      expect(back.traceHz, 10);
      expect(back.velocityTrace, hasLength(101));
      expect(back.hasVideo, isTrue);
    });

    test('copyWith keeps everything else', () {
      final s = videoSet().copyWith(videoOffsetSec: 0.3, rpe: 8.5);
      expect(s.videoOffsetSec, 0.3);
      expect(s.rpe, 8.5);
      expect(s.reps, hasLength(2));
      expect(s.velocityTrace, hasLength(101));
    });

    test('Session.replaceSet swaps by id', () {
      final session = Session(
        id: 'x', exerciseId: 'squat_low_bar',
        startedAt: DateTime.utc(2026), sets: [videoSet()],
      );
      final updated = session.replaceSet(videoSet().copyWith(videoOffsetSec: 2));
      expect(updated.sets.single.videoOffsetSec, 2);
    });

    test('downsampleTrace targets ~50 Hz', () {
      final (v, hz) = downsampleTrace(List.filled(2000, 1.0), 200);
      expect(hz, 50);
      expect(v, hasLength(500));
      final (v2, hz2) = downsampleTrace(List.filled(10, 1.0), 30);
      expect(hz2, 30); // already below target: kept as is
      expect(v2, hasLength(10));
    });
  });

  group('VideoSettingsStore', () {
    test('persists and reloads settings', () async {
      final dir = await Directory.systemTemp.createTemp('video_settings');
      addTearDown(() => dir.delete(recursive: true));
      final a = VideoSettingsStore(baseDirectory: () async => dir);
      await a.update(const VideoSettings(
          lens: VideoLens.front, quality: VideoQuality.uhd, fps: 60));
      final b = VideoSettingsStore(baseDirectory: () async => dir);
      await b.load();
      expect(b.value, a.value);
      expect(b.value.lens, VideoLens.front);
    });

    test('missing or corrupt file gives defaults', () async {
      final dir = await Directory.systemTemp.createTemp('video_settings');
      addTearDown(() => dir.delete(recursive: true));
      File('${dir.path}/video_settings.json').writeAsStringSync('{nope');
      final s = VideoSettingsStore(baseDirectory: () async => dir);
      await s.load();
      expect(s.value, const VideoSettings());
    });
  });
}
