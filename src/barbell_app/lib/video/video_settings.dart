import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Lens and quality options mirroring the reference app's
/// `VideoCaptureConfig` (`VideoLens` Back/Front, `VideoQuality` 720p/1080p/4K).
enum VideoLens {
  back('Back', CameraLensDirection.back),
  front('Front', CameraLensDirection.front);

  const VideoLens(this.label, this.direction);
  final String label;
  final CameraLensDirection direction;
}

enum VideoQuality {
  hd('720p', ResolutionPreset.high),
  fhd('1080p', ResolutionPreset.veryHigh),
  uhd('4K', ResolutionPreset.ultraHigh);

  const VideoQuality(this.label, this.preset);
  final String label;
  final ResolutionPreset preset;
}

@immutable
class VideoSettings {
  const VideoSettings({
    this.enabled = false,
    this.lens = VideoLens.back,
    this.quality = VideoQuality.fhd,
    this.fps = 30,
    this.audio = false,
  });

  factory VideoSettings.fromJson(Map<String, dynamic> j) => VideoSettings(
        enabled: j['enabled'] as bool? ?? false,
        lens: VideoLens.values.firstWhere((l) => l.name == j['lens'],
            orElse: () => VideoLens.back),
        quality: VideoQuality.values.firstWhere((q) => q.name == j['quality'],
            orElse: () => VideoQuality.fhd),
        fps: j['fps'] as int? ?? 30,
        audio: j['audio'] as bool? ?? false,
      );

  /// Record video alongside the sensor on the set screen.
  final bool enabled;
  final VideoLens lens;
  final VideoQuality quality;

  /// 30 or 60. Not every device supports 60 at every resolution.
  final int fps;

  /// Record sound (needs microphone permission).
  final bool audio;

  VideoSettings copyWith({
    bool? enabled,
    VideoLens? lens,
    VideoQuality? quality,
    int? fps,
    bool? audio,
  }) =>
      VideoSettings(
        enabled: enabled ?? this.enabled,
        lens: lens ?? this.lens,
        quality: quality ?? this.quality,
        fps: fps ?? this.fps,
        audio: audio ?? this.audio,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'lens': lens.name,
        'quality': quality.name,
        'fps': fps,
        'audio': audio,
      };

  @override
  bool operator ==(Object other) =>
      other is VideoSettings &&
      other.enabled == enabled &&
      other.lens == lens &&
      other.quality == quality &&
      other.fps == fps &&
      other.audio == audio;

  @override
  int get hashCode => Object.hash(enabled, lens, quality, fps, audio);
}

/// Persists [VideoSettings] in `<base>/video_settings.json`.
class VideoSettingsStore extends ValueNotifier<VideoSettings> {
  VideoSettingsStore({Future<Directory> Function()? baseDirectory})
      : _base = baseDirectory ?? getApplicationDocumentsDirectory,
        super(const VideoSettings());

  final Future<Directory> Function() _base;

  Future<File> _file() async => File('${(await _base()).path}/video_settings.json');

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        value = VideoSettings.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Reading video settings failed: $e');
    }
  }

  Future<void> update(VideoSettings s) async {
    value = s;
    try {
      await (await _file()).writeAsString(jsonEncode(s.toJson()));
    } catch (e) {
      debugPrint('Saving video settings failed: $e');
    }
  }
}
