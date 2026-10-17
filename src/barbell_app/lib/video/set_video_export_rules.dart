import 'dart:typed_data';

import '../workout/session.dart';

/// Pure rules for exporting a set's video with the metrics overlay burned
/// in, ported from the reference app's `SetVideoExportRules`,
/// `SetVideoExportOutputRules`, `SetMetricsOverlay` (its timing) and
/// `VideoExportDiskCapRules`. The encode itself is native
/// (`SetVideoExporter`).

/// Kept before the first rep and after the last (`REP_BUFFER_MS`).
const repBufferMs = 10000;

/// The bar stays full this long after a rep ends (`REVERSE_DELAY_MS`)...
const reverseDelayMs = 200;

/// ...then empties over this long (`REVERSE_DURATION_MS`).
const reverseDurationMs = 300;

/// The export cache is trimmed to this size (`MAX_TOTAL_BYTES`, 500 MB).
const exportCacheMaxBytes = 524288000;

/// One rep as the overlay shows it, on the *cropped* clip's time base.
class RepOverlayWindow {
  const RepOverlayWindow({
    required this.number,
    required this.startMs,
    required this.endMs,
    this.meanVelocityMps,
    this.stickingBand,
  });

  final int number;
  final int startMs, endMs;

  /// Null when the rep has no positive mean velocity (shown dimmed as 0.00).
  final double? meanVelocityMps;

  /// Orange band as 0–1 fractions of the bar, if any.
  final (double, double)? stickingBand;

  @override
  bool operator ==(Object other) =>
      other is RepOverlayWindow &&
      other.number == number &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      other.meanVelocityMps == meanVelocityMps &&
      other.stickingBand == stickingBand;

  @override
  int get hashCode =>
      Object.hash(number, startMs, endMs, meanVelocityMps, stickingBand);

  @override
  String toString() =>
      'RepOverlayWindow($number, $startMs–$endMs ms, $meanVelocityMps, $stickingBand)';
}

/// Where to cut the source video and the reps inside the cut.
class SetVideoExportPlan {
  const SetVideoExportPlan({
    required this.cropStartMs,
    required this.cropEndMs,
    required this.repWindows,
  });

  /// Source-video positions.
  final int cropStartMs, cropEndMs;
  final List<RepOverlayWindow> repWindows;

  int get durationMs => cropEndMs - cropStartMs;
}

/// What an export needs to know about a set (`SetVideoOverlayInput`).
class SetVideoOverlayInput {
  const SetVideoOverlayInput({
    required this.setId,
    required this.videoPath,
    required this.weightLabel,
    required this.repsCount,
    required this.repWindowsSec,
    required this.repMeanVelocitiesMps,
    this.repStickingBandsPct = const [],
  });

  /// From a stored set. Rep windows are moved onto the video's time base
  /// with the set's sync offset; the reference app assumes video t = 0 is
  /// the recording's start, i.e. an offset of 0.
  factory SetVideoOverlayInput.fromSet(
    SetRecord set, {
    required String videoPath,
    required String weightLabel,
  }) {
    final offset = set.videoOffsetSec ?? 0;
    return SetVideoOverlayInput(
      setId: set.id,
      videoPath: videoPath,
      weightLabel: weightLabel,
      repsCount: set.reps.length,
      repWindowsSec: [
        for (final r in set.reps) (r.startSec + offset, r.endSec + offset),
      ],
      repMeanVelocitiesMps: [for (final r in set.reps) r.meanVelocity],
      repStickingBandsPct: [
        for (final r in set.reps)
          r.sticking == null ? null : (r.sticking!.startPct, r.sticking!.endPct),
      ],
    );
  }

  final String setId;
  final String videoPath;
  final String weightLabel;
  final int repsCount;

  /// Concentric windows, seconds of *video* time.
  final List<(double, double)> repWindowsSec;
  final List<double> repMeanVelocitiesMps;

  /// Orange sticking band per rep, 0–100 %, or null.
  final List<(double, double)?> repStickingBandsPct;
}

/// `SetVideoExportRules.buildPlan`: crop from [repBufferMs] before the
/// earliest rep start to [repBufferMs] after the latest rep end, clamped
/// to the video. Null when there are no reps, no duration, or nothing left
/// after clamping (then there is no export).
///
/// Rep windows are moved onto the clip (start at 0) and clamped at 0 only;
/// they are not clamped to the clip's end.
SetVideoExportPlan? buildExportPlan({
  required List<(double, double)> repWindowsSec,
  required List<double> repMeanVelocitiesMps,
  required int videoDurationMs,
  List<(double, double)?> repStickingBandsPct = const [],
}) {
  if (repWindowsSec.isEmpty || videoDurationMs <= 0) return null;
  int ms(double sec) => (sec * 1000).truncate();
  int clampToVideo(int v) => v.clamp(0, videoDurationMs);
  var first = clampToVideo(ms(repWindowsSec.first.$1));
  var last = clampToVideo(ms(repWindowsSec.first.$2));
  for (final (s, e) in repWindowsSec) {
    final cs = clampToVideo(ms(s)), ce = clampToVideo(ms(e));
    if (cs < first) first = cs;
    if (ce > last) last = ce;
  }
  final cropStart = (first - repBufferMs) < 0 ? 0 : first - repBufferMs;
  final cropEnd = (last + repBufferMs) > videoDurationMs
      ? videoDurationMs
      : last + repBufferMs;
  if (cropEnd <= cropStart) return null;

  final windows = <RepOverlayWindow>[];
  for (var i = 0; i < repWindowsSec.length; i++) {
    final (s, e) = repWindowsSec[i];
    final v = i < repMeanVelocitiesMps.length ? repMeanVelocitiesMps[i] : null;
    windows.add(RepOverlayWindow(
      number: i + 1,
      startMs: _atLeastZero(ms(s) - cropStart),
      endMs: _atLeastZero(ms(e) - cropStart),
      meanVelocityMps: v == null || v <= 0 ? null : v,
      stickingBand: stickingBandFraction(
          i < repStickingBandsPct.length ? repStickingBandsPct[i] : null),
    ));
  }
  return SetVideoExportPlan(
      cropStartMs: cropStart, cropEndMs: cropEnd, repWindows: windows);
}

int _atLeastZero(int v) => v < 0 ? 0 : v;

/// Band in percent → 0–1 fractions; null if missing, empty or inverted.
(double, double)? stickingBandFraction((double, double)? bandPct) {
  if (bandPct == null) return null;
  final (start, end) = bandPct;
  if (end <= 0) return null;
  final s = (start / 100).clamp(0.0, 1.0), e = (end / 100).clamp(0.0, 1.0);
  if (e <= s) return null;
  return (s, e);
}

/// Smoothstep on 0–1 (`easeInOut`).
double easeInOut(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

/// How full the overlay's progress bar is at clip time [timeMs], and for
/// which rep (index into `repWindows`, or -1 when empty).
///
/// The bar fills with [easeInOut] across a rep, stays full for
/// [reverseDelayMs], then empties over [reverseDurationMs]. After the last
/// rep it stays full.
(double, int) barFillState(SetVideoExportPlan plan, int timeMs) {
  final reps = plan.repWindows;
  for (var i = 0; i < reps.length; i++) {
    final r = reps[i];
    if (timeMs < r.startMs) continue;
    final span = r.endMs - r.startMs < 1 ? 1 : r.endMs - r.startMs;
    if (timeMs <= r.endMs) return (easeInOut((timeMs - r.startMs) / span), i);
    if (i == reps.length - 1) return (1, i);
    if (timeMs <= r.endMs + reverseDelayMs) return (1, i);
    if (timeMs <= r.endMs + reverseDelayMs + reverseDurationMs) {
      return (
        1 - easeInOut((timeMs - r.endMs - reverseDelayMs) / reverseDurationMs),
        i,
      );
    }
  }
  return (0, -1);
}

/// The rep whose window contains [timeMs] (index, or -1). Only then does
/// the overlay show a rep number and mean velocity.
int activeRepIndex(SetVideoExportPlan plan, int timeMs) {
  final reps = plan.repWindows;
  for (var i = 0; i < reps.length; i++) {
    if (reps[i].startMs <= timeMs && timeMs <= reps[i].endMs) return i;
  }
  return -1;
}

/// The overlay's animation state sampled every [stepMs] over the clip, so
/// the native renderer only draws and all timing rules stay here.
class OverlaySamples {
  OverlaySamples(this.stepMs, this.fill, this.barRep, this.activeRep);

  factory OverlaySamples.of(SetVideoExportPlan plan, {int stepMs = 10}) {
    final n = plan.durationMs ~/ stepMs + 1;
    final fill = Float32List(n);
    final bar = Int32List(n);
    final active = Int32List(n);
    for (var k = 0; k < n; k++) {
      final (f, i) = barFillState(plan, k * stepMs);
      fill[k] = f;
      bar[k] = i;
      active[k] = activeRepIndex(plan, k * stepMs);
    }
    return OverlaySamples(stepMs, fill, bar, active);
  }

  final int stepMs;
  final Float32List fill;
  final Int32List barRep, activeRep;
}

/// Panel texts: "Bar Speed", then `"<weight> x <reps>"` (`SetMetricsOverlay`).
String overlayWeightLine(String weightLabel, int repsCount) =>
    '$weightLabel x $repsCount';

/// The active rep's mean velocity text; 0.00 when unknown.
String overlayVelocityText(double? v) => (v ?? 0).toStringAsFixed(2);

/// `SetVideoExportOutputRules.outputBaseName`. Save and share use the
/// uncapped export, which gets the `_4k` suffix.
String exportBaseName(String setId, {int? maxShortSidePx}) =>
    'overlay_set_$setId${maxShortSidePx == null ? '_4k' : ''}';

String _signatureVariantToken(int? maxShortSidePx) =>
    maxShortSidePx?.toString() ?? 'full';

/// Java/Kotlin `String.hashCode`.
int javaStringHash(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (31 * h + c) & 0xFFFFFFFF;
  }
  return h >= 0x80000000 ? h - 0x100000000 : h;
}

/// `SetVideoExporter.signature`: identifies the inputs an export was made
/// from; a cached export is reused only while it matches.
String exportSignature(SetVideoOverlayInput input, {int? maxShortSidePx}) {
  final windows = input.repWindowsSec
      .map((w) => '${w.$1.toStringAsFixed(3)}-${w.$2.toStringAsFixed(3)}')
      .join(';');
  final velocities =
      input.repMeanVelocitiesMps.map((v) => v.toStringAsFixed(3)).join(';');
  final joined = [
    input.videoPath,
    input.weightLabel,
    '${input.repsCount}',
    windows,
    velocities,
  ].join('|');
  return '${javaStringHash(joined)}@${_signatureVariantToken(maxShortSidePx)}';
}

/// A file in the export cache.
class SizedFile {
  const SizedFile(this.name, this.lastModifiedMs, this.lengthBytes);
  final String name;
  final int lastModifiedMs, lengthBytes;
}

/// `VideoExportDiskCapRules.namesToDeleteToEnforceCap`: oldest first until
/// the total fits, deleting an export's `.mp4` and `.sig` together.
Set<String> namesToDeleteToEnforceCap(List<SizedFile> files, int maxTotalBytes) {
  if (files.isEmpty || maxTotalBytes < 0) return {};
  int len(SizedFile f) => f.lengthBytes < 0 ? 0 : f.lengthBytes;
  var total = files.fold<int>(0, (a, f) => a + len(f));
  if (total <= maxTotalBytes) return {};
  final byName = {for (final f in files) f.name: f};
  final oldestFirst = [...files]
    ..sort((a, b) => a.lastModifiedMs.compareTo(b.lastModifiedMs));
  final out = <String>{};
  for (final f in oldestFirst) {
    if (total <= maxTotalBytes) break;
    if (out.contains(f.name)) continue;
    for (final n in _pairNames(f.name, byName.keys.toSet())) {
      if (out.add(n)) total -= byName[n] == null ? 0 : len(byName[n]!);
    }
  }
  return out;
}

List<String> _pairNames(String name, Set<String> known) {
  final String stem;
  if (name.endsWith('.mp4')) {
    stem = name.substring(0, name.length - 4);
  } else if (name.endsWith('.sig')) {
    stem = name.substring(0, name.length - 4);
  } else {
    return [name];
  }
  final pair = [
    for (final n in ['$stem.mp4', '$stem.sig'])
      if (known.contains(n) || n == name) n,
  ];
  return pair.isEmpty ? [name] : pair.toSet().toList();
}
