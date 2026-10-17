import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'video_settings.dart';

/// A finished clip and when it started on the phone clock.
class RecordedClip {
  const RecordedClip(this.file, this.startHostTimeUs);
  final File file;

  /// Phone clock (µs since epoch) when recording began. Compared with the
  /// sensor recording's origin to sync the overlay.
  final int startHostTimeUs;
}

/// Camera preview and video recording for the set screen.
///
/// The reference app assumes video t = 0 is the sensor recording's start;
/// here the start is timestamped instead, so the offset can be stored (and
/// nudged in the player if the camera's start latency was unusual).
class SetVideoRecorder extends ChangeNotifier {
  SetVideoRecorder({Future<Directory> Function()? baseDirectory})
      : _base = baseDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _base;

  CameraController? _controller;
  VideoSettings? _openedWith;
  String? _error;
  int? _startUs;
  bool _busy = false;

  CameraController? get controller => _controller;
  bool get isReady => _controller?.value.isInitialized ?? false;
  bool get isRecording => _controller?.value.isRecordingVideo ?? false;
  String? get error => _error;

  /// Open (or reopen) the camera for [settings]. Safe to call repeatedly.
  Future<void> open(VideoSettings settings) async {
    if (_busy) return;
    if (isReady && _openedWith == settings) return;
    _busy = true;
    try {
      await _disposeController();
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('none', 'No camera found');
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == settings.lens.direction,
        orElse: () => cameras.first,
      );
      final c = CameraController(
        cam,
        settings.quality.preset,
        enableAudio: settings.audio,
        fps: settings.fps,
      );
      await c.initialize();
      await c.prepareForVideoRecording();
      _controller = c;
      _openedWith = settings;
      _error = null;
    } on CameraException catch (e) {
      _error = e.description ?? e.code;
    } catch (e) {
      _error = '$e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> start() async {
    final c = _controller;
    if (c == null || !isReady || isRecording) return;
    final before = DateTime.now().microsecondsSinceEpoch;
    await c.startVideoRecording();
    final after = DateTime.now().microsecondsSinceEpoch;
    // The first frame lands somewhere inside the call; take the midpoint.
    _startUs = (before + after) ~/ 2;
    notifyListeners();
  }

  /// Stop and move the clip to `<base>/videos/<name>.mp4`.
  Future<RecordedClip?> stop(String name) async {
    final c = _controller;
    final startUs = _startUs;
    if (c == null || !isRecording || startUs == null) return null;
    _startUs = null;
    try {
      final x = await c.stopVideoRecording();
      final dir = await Directory('${(await _base()).path}/videos')
          .create(recursive: true);
      final ext = x.path.contains('.') ? x.path.split('.').last : 'mp4';
      final dest = File('${dir.path}/$name.$ext');
      try {
        await File(x.path).rename(dest.path);
      } on FileSystemException {
        await File(x.path).copy(dest.path); // different volume
        await File(x.path).delete();
      }
      return RecordedClip(dest, startUs);
    } catch (e) {
      _error = 'Saving video failed: $e';
      return null;
    } finally {
      notifyListeners();
    }
  }

  /// Path of [file] relative to the documents directory, for storage.
  static String relativePath(File file) => 'videos/${file.uri.pathSegments.last}';

  Future<File> resolve(String relative) async => File('${(await _base()).path}/$relative');

  Future<void> close() async {
    await _disposeController();
    notifyListeners();
  }

  Future<void> _disposeController() async {
    final c = _controller;
    _controller = null;
    _openedWith = null;
    if (c == null) return;
    if (c.value.isRecordingVideo) {
      try {
        await c.stopVideoRecording();
      } catch (_) {}
    }
    await c.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }
}
