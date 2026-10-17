import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'set_video_export_rules.dart';

/// Exports a set's video cropped to its reps with the metrics overlay
/// burned in, and saves or shares it, like the reference app's
/// `SetVideoExporter` and `FeedbackVideoViewModel`.
///
/// The encode runs natively through Media3 Transformer on Android
/// (`SetVideoExportChannel.kt`), as in the reference app. Other platforms
/// have no encoder; [export] returns null there and save/share fall back
/// to the raw video, which is what the reference app does when its export
/// fails.
class SetVideoExporter {
  SetVideoExporter({Future<Directory> Function()? baseDirectory})
      : _base = baseDirectory ?? getApplicationDocumentsDirectory;

  static const _channel = MethodChannel('barbell_app/set_video_export');

  final Future<Directory> Function() _base;
  Future<void> _lock = Future.value();
  bool _cancelled = false;

  /// `<docs>/video_exports/`. Not `videos/`: that holds the raw clips.
  Future<Directory> _exportDir() async =>
      Directory('${(await _base()).path}/video_exports').create(recursive: true);

  Future<File> _file(String setId, String ext) async =>
      File('${(await _exportDir()).path}/${exportBaseName(setId)}.$ext');

  /// The finished export for [input] if one matches its signature.
  Future<File?> cachedExport(SetVideoOverlayInput input) async {
    final mp4 = await _file(input.setId, 'mp4');
    if (!await mp4.exists()) return null;
    try {
      final sig = await (await _file(input.setId, 'sig')).readAsString();
      return sig == exportSignature(input) ? mp4 : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Full-resolution export with the overlay, or null if there are no reps
  /// to crop to, the video can't be read, or the encode failed or was
  /// cancelled. Exports run one at a time.
  Future<File?> export(SetVideoOverlayInput input) {
    final done = Completer<void>();
    final previous = _lock;
    _lock = done.future;
    return previous.then((_) => _export(input)).whenComplete(done.complete);
  }

  Future<File?> _export(SetVideoOverlayInput input) async {
    final cached = await cachedExport(input);
    if (cached != null) return cached;
    try {
      final meta = await _channel
          .invokeMapMethod<String, Object?>('probe', {'path': input.videoPath});
      final durationMs = (meta?['durationMs'] as num?)?.toInt();
      if (durationMs == null) return null;
      final plan = buildExportPlan(
        repWindowsSec: input.repWindowsSec,
        repMeanVelocitiesMps: input.repMeanVelocitiesMps,
        videoDurationMs: durationMs,
        repStickingBandsPct: input.repStickingBandsPct,
      );
      if (plan == null) return null;
      final out = await _file(input.setId, 'mp4');
      if (await out.exists()) await out.delete();
      final samples = OverlaySamples.of(plan);
      final ok = await _channel.invokeMethod<bool>('export', {
        'input': input.videoPath,
        'output': out.path,
        'cropStartMs': plan.cropStartMs,
        'cropEndMs': plan.cropEndMs,
        'weightLine': overlayWeightLine(input.weightLabel, input.repsCount),
        'repNumbers': [for (final r in plan.repWindows) '${r.number}'],
        'repVelocities': [
          for (final r in plan.repWindows) overlayVelocityText(r.meanVelocityMps),
        ],
        'repHasVelocity': [
          for (final r in plan.repWindows) r.meanVelocityMps != null,
        ],
        'repBands': [
          for (final r in plan.repWindows)
            r.stickingBand == null
                ? null
                : [r.stickingBand!.$1, r.stickingBand!.$2],
        ],
        'stepMs': samples.stepMs,
        'fill': samples.fill,
        'barRep': samples.barRep,
        'activeRep': samples.activeRep,
      });
      if (ok != true || !await out.exists()) {
        if (await out.exists()) await out.delete();
        return null;
      }
      await (await _file(input.setId, 'sig'))
          .writeAsString(exportSignature(input));
      await _enforceSizeCap();
      return out;
    } on MissingPluginException {
      return null; // no encoder on this platform
    } on PlatformException catch (e) {
      debugPrint('Video export failed: ${e.message}');
      return null;
    }
  }

  /// Stop the running encode, if any (the reference app does this when the
  /// player is dismissed). Its [export] call then returns null.
  Future<void> cancel() async {
    _cancelled = true;
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // nothing to cancel
    } on PlatformException {
      // already finished
    }
  }

  /// Delete [setId]'s export, e.g. after its reps change.
  Future<void> invalidate(String setId) async {
    for (final ext in ['mp4', 'sig']) {
      final f = await _file(setId, ext);
      if (await f.exists()) await f.delete();
    }
  }

  Future<void> _enforceSizeCap() async {
    final dir = await _exportDir();
    final files = <SizedFile>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final s = await e.stat();
      files.add(SizedFile(e.uri.pathSegments.last,
          s.modified.millisecondsSinceEpoch, s.size));
    }
    for (final n in namesToDeleteToEnforceCap(files, exportCacheMaxBytes)) {
      try {
        await File('${dir.path}/$n').delete();
      } on FileSystemException {
        // already gone
      }
    }
  }

  /// `sourceUriForSaveOrShare`: the overlay export, else the raw video.
  /// Null when there is neither, or the export was cancelled.
  Future<File?> _source(SetVideoOverlayInput input) async {
    _cancelled = false;
    final exported = await export(input);
    if (_cancelled) return null;
    if (exported != null) return exported;
    final raw = File(input.videoPath);
    return await raw.exists() ? raw : null;
  }

  /// Copy of the export (or raw video) in the temp `share_videos/` folder,
  /// or null ("Could not prepare video"), then the system share sheet.
  Future<bool> share(SetVideoOverlayInput input) async {
    final src = await _source(input);
    if (src == null) return false;
    final File copy;
    try {
      final dir = await Directory('${(await getTemporaryDirectory()).path}/share_videos')
          .create(recursive: true);
      copy = await src.copy(
          '${dir.path}/share_set_${DateTime.now().millisecondsSinceEpoch}.mp4');
    } on FileSystemException {
      return false;
    }
    await SharePlus.instance.share(
        ShareParams(files: [XFile(copy.path, mimeType: 'video/mp4')]));
    return true;
  }

  /// Save the export (or raw video) to the gallery's "Barbell Tracker"
  /// album as `barbell_set_<ms>.mp4`. False on any failure.
  Future<bool> saveToGallery(SetVideoOverlayInput input) async {
    final src = await _source(input);
    if (src == null) return false;
    File? copy;
    try {
      if (!await Gal.hasAccess(toAlbum: true) &&
          !await Gal.requestAccess(toAlbum: true)) {
        return false;
      }
      copy = await src.copy('${(await getTemporaryDirectory()).path}/'
          'barbell_set_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await Gal.putVideo(copy.path, album: galleryAlbum);
      return true;
    } on GalException catch (e) {
      debugPrint('Save to gallery failed: ${e.type.message}');
      return false;
    } on FileSystemException {
      return false;
    } finally {
      try {
        await copy?.delete();
      } on FileSystemException {
        // temp file, ignore
      }
    }
  }

  /// The reference app saves to `Movies/Stance`.
  static const galleryAlbum = 'Barbell Tracker';
}
