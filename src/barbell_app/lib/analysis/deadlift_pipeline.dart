/// Port of the reference app's Kotlin `DeadliftTcnPipeline` and
/// `DeadliftSignalProcessing` (notes §4, §10): integrate vertical
/// acceleration at a fixed 5 ms step, correct drift with the U-Net
/// ("Nina"), segment reps with the TCN, and take "silver" per-rep metrics.
library;

import 'dart:math' as math;

import 'motion_mapper.dart';

/// Runs one model window: flat float input → flat float output.
abstract class ModelRunner {
  List<double> predict(List<double> input);
}

class DeadliftModelsRunners {
  const DeadliftModelsRunners({required this.unet, required this.tcn});
  final ModelRunner unet;
  final ModelRunner tcn;
}

class DeadliftRep {
  const DeadliftRep(this.startSec, this.endSec, this.meanVelocity, this.peakVelocity);
  final double startSec, endSec, meanVelocity, peakVelocity;
}

class DeadliftResult {
  const DeadliftResult(this.reps, this.correctedVelocity);
  final List<DeadliftRep> reps;

  /// Nina-corrected velocity, 200 Hz assumed.
  final List<double> correctedVelocity;
}

class DeadliftTcnPipeline {
  DeadliftTcnPipeline(this.models);

  final DeadliftModelsRunners models;

  // Model metadata (assets/models/deadlift/*.metadata.json).
  static const unetWindow = 2000;
  static const unetStride = 100;
  static const tcnWindow = 1000;
  static const tcnStride = 300;
  static const tcnMean = 0.008150167763233185;
  static const tcnStd = 0.22332538664340973;

  static const dt = 0.005;
  static const sampleRate = 200.0;

  DeadliftResult process(MappedMotion motion) {
    if (motion.length == 0) throw ArgumentError('empty recording');
    final times = motion.timeSec;
    final raw = integrateRawVelocity(motion);
    final corrected = applyNinaCorrected(raw, runUnet(raw));
    final normalised = [for (final v in corrected) (v - tcnMean) / (tcnStd + 1e-8)];
    final reps = <DeadliftRep>[];
    for (final (start, end) in extractReps(runTcn(normalised), times)) {
      final m = silverMetrics(raw, times, start, end);
      if (m != null) reps.add(m);
    }
    return DeadliftResult(reps, corrected);
  }

  /// World-Z acceleration minus 1 g, bias from the first 20 samples
  /// removed, integrated with a fixed 5 ms step (timestamps ignored).
  static List<double> integrateRawVelocity(MappedMotion motion) {
    final a = [for (final s in motion.samples) (s.worldZ - 1.0) * 9.81];
    final nBias = math.min(a.length, 20);
    var bias = 0.0;
    for (var i = 0; i < nBias; i++) {
      bias += a[i];
    }
    bias /= nBias;
    var v = 0.0;
    return [
      for (final x in a) v += (x - bias) * dt,
    ];
  }

  List<double> runUnet(List<double> raw) {
    if (raw.isEmpty) return const [];
    var x = List<double>.of(raw);
    if (x.length < unetWindow) x = reflectPadRight(x, unetWindow - x.length);
    final rem = (x.length - unetWindow) % unetStride;
    if (rem != 0) x = reflectPadRight(x, unetStride - rem);
    final acc = List<double>.filled(x.length, 0);
    final cnt = List<double>.filled(x.length, 0);
    for (var i = 0; i + unetWindow <= x.length; i += unetStride) {
      final out = models.unet.predict(x.sublist(i, i + unetWindow));
      for (var k = 0; k < unetWindow; k++) {
        acc[i + k] += out[k];
        cnt[i + k] += 1;
      }
    }
    return [for (var i = 0; i < raw.length; i++) acc[i] / math.max(cnt[i], 1)];
  }

  /// Keep the raw velocity's shape inside each detected rep region but swap
  /// its straight-line trend for the reconstruction's.
  static List<double> applyNinaCorrected(List<double> raw, List<double> recon) {
    if (raw.length != recon.length || recon.isEmpty) return List.of(recon);
    final regions = detectRegions(recon);
    if (regions == null) return List.of(recon);
    final out = List<double>.of(recon);
    final (peaks, left, right) = regions;
    for (var i = 0; i < peaks.length; i += 2) {
      final a = math.max(0, math.min(left[i], raw.length - 1));
      final b = math.max(a, math.min(right[i], raw.length));
      final n = b - a;
      if (n < 2) continue;
      final rawLine = linspace(raw[a], raw[b - 1], n);
      final recLine = linspace(recon[a], recon[math.min(b - 1, recon.length - 1)], n);
      for (var k = 0; k < n; k++) {
        out[a + k] = raw[a + k] - rawLine[k] + recLine[k];
      }
    }
    return out;
  }

  static (List<int>, List<int>, List<int>)? detectRegions(List<double> recon) {
    final energy = uniformFilter1d([for (final v in recon) v * v], 60);
    final maxE = energy.reduce(math.max);
    if (!(maxE > 0)) return null;
    final peaks = findProminentPeaks(energy, 100, maxE * 0.05);
    if (peaks.isEmpty) return null;
    final widths = peakWidths(energy, peaks, 0.95);
    final lefts = [for (final w in widths) w.$1.round()];
    final rights = [for (final w in widths) w.$2.round()];
    final crossings = {...lefts, ...rights}.toList()..sort();
    final l = List<int>.of(lefts), r = List<int>.of(rights);
    for (var i = 0; i < peaks.length; i++) {
      final p = peaks[i];
      final below = crossings.where((c) => c <= p);
      if (below.isNotEmpty) l[i] = below.reduce(math.max);
      final above = crossings.where((c) => c >= p);
      if (above.isNotEmpty) r[i] = above.reduce(math.min);
    }
    final pk = List<int>.of(peaks);
    _mergeSameSign(recon, pk, l, r);
    if (!_passesQualityGate(recon, pk)) return null;
    return (pk, l, r);
  }

  static void _mergeSameSign(List<double> recon, List<int> p, List<int> l, List<int> r) {
    var i = 0;
    while (i < p.length - 1) {
      final a = p[i], b = p[i + 1];
      if (_sign(recon[a]) == _sign(recon[b]) && b - a < 400) {
        p[i] = recon[b].abs() > recon[a].abs() ? b : a;
        l[i] = math.min(l[i], l[i + 1]);
        r[i] = math.max(r[i], r[i + 1]);
        p.removeAt(i + 1);
        l.removeAt(i + 1);
        r.removeAt(i + 1);
      } else {
        i++;
      }
    }
  }

  static bool _passesQualityGate(List<double> recon, List<int> peaks) {
    if (peaks.isEmpty || peaks.length.isOdd) return false;
    for (var i = 0; i < peaks.length - 1; i++) {
      if (_sign(recon[peaks[i]]) == _sign(recon[peaks[i + 1]])) return false;
    }
    return true;
  }

  List<double> runTcn(List<double> x) {
    final n = x.length;
    if (n == 0) return const [];
    final acc = List<double>.filled(n, 0);
    final cnt = List<double>.filled(n, 0);
    var i = 0;
    while (i < n) {
      final end = i + tcnWindow;
      final take = math.min(tcnWindow, n - i);
      final window = List<double>.filled(tcnWindow, 0)..setRange(0, take, x, i);
      final prob = toProbabilities(models.tcn.predict(window));
      for (var k = 0; k < take; k++) {
        acc[i + k] += prob[k];
        cnt[i + k] += 1;
      }
      i += tcnStride;
      if (end >= n) break;
    }
    return [for (var k = 0; k < n; k++) acc[k] / math.max(cnt[k], 1)];
  }

  /// Pair rising/falling edges of the smoothed lift probability.
  static List<(double, double)> extractReps(List<double> prob, List<double> times) {
    if (prob.length <= 2) return const [];
    final t = resolveTimes(times, prob.length);
    final step = medianDelta(t) ?? dt;
    final grad = gradient(gaussianFilter1d(prob, 0.05 / step));
    final rises = findPeaks(grad, 0.008);
    final falls = findPeaks([for (final g in grad) -g], 0.008);
    if (rises.isEmpty || falls.isEmpty) return const [];
    final events = [
      for (final r in rises) (true, r),
      for (final f in falls) (false, f),
    ]..sort((a, b) => a.$2.compareTo(b.$2));

    final pairs = <(int, int)>[];
    int? open;
    for (final (isRise, idx) in events) {
      if (isRise) {
        open ??= idx;
      } else if (open != null) {
        pairs.add((open, idx));
        open = null;
      }
    }
    if (pairs.isEmpty) return const [];

    final minGap = (0.2 / step).round();
    final merged = [pairs.first];
    for (final p in pairs.skip(1)) {
      if (p.$1 - merged.last.$2 <= minGap) {
        merged[merged.length - 1] = (merged.last.$1, p.$2);
      } else {
        merged.add(p);
      }
    }
    final out = <(double, double)>[];
    for (final (a, b) in merged) {
      final s = t[math.max(0, math.min(a, t.length - 1))];
      final e = t[math.max(0, math.min(b, t.length - 1))];
      final d = e - s;
      if (d >= 0.3 && d <= 8.0) out.add((s, e));
    }
    return out;
  }

  /// Mean and peak |v| after removing the straight line between the rep's
  /// endpoints (bar assumed still at both ends).
  static DeadliftRep? silverMetrics(
      List<double> raw, List<double> times, double start, double end) {
    if (raw.length <= 1) return null;
    final t = resolveTimes(times, raw.length);
    final i0 = nearestIndex(t, start), i1 = nearestIndex(t, end);
    if (i1 <= i0) return null;
    final seg = raw.sublist(i0, i1 + 1);
    final line = linspace(seg.first, seg.last, seg.length);
    var total = 0.0, peak = 0.0;
    for (var k = 0; k < seg.length; k++) {
      final a = (seg[k] - line[k]).abs();
      total += a;
      peak = math.max(peak, a);
    }
    return DeadliftRep(start, end, total / seg.length, peak);
  }

  // -------------------------------------------- DeadliftSignalProcessing

  static int _sign(double v) => v > 0 ? 1 : (v < 0 ? -1 : 0);

  static int _reflectIncluding(int index, int count) {
    if (count <= 1) return 0;
    while (index < 0 || index >= count) {
      index = index < 0 ? -index - 1 : 2 * count - index - 1;
    }
    return index;
  }

  static int _reflectExcluding(int index, int count) {
    if (count <= 1) return 0;
    final period = 2 * count - 2;
    var m = index % period;
    if (m < 0) m += period;
    return m < count ? m : period - m;
  }

  static List<double> reflectPadRight(List<double> x, int pad) {
    if (pad <= 0) return List.of(x);
    if (x.length <= 1) {
      return [...x, for (var i = 0; i < pad; i++) x.isEmpty ? 0.0 : x.first];
    }
    return [
      ...x,
      for (var i = 1; i <= pad; i++) x[_reflectExcluding(x.length - 1 + i, x.length)],
    ];
  }

  /// scipy `uniform_filter1d` (reflect mode).
  static List<double> uniformFilter1d(List<double> x, int size) {
    if (x.isEmpty || size <= 1) return List.of(x);
    final half = size ~/ 2;
    return [
      for (var i = 0; i < x.length; i++)
        () {
          var s = 0.0;
          for (var k = 0; k < size; k++) {
            s += x[_reflectIncluding(i + k - half, x.length)];
          }
          return s / size;
        }(),
    ];
  }

  /// scipy `gaussian_filter1d` (reflect mode, truncate 4).
  static List<double> gaussianFilter1d(List<double> x, double sigma) {
    if (x.isEmpty || sigma <= 0) return List.of(x);
    final radius = math.max(1, (4 * sigma + 0.5).toInt());
    final kernel = [
      for (var k = -radius; k <= radius; k++) math.exp(-(k * k) / (2 * sigma * sigma)),
    ];
    final norm = kernel.reduce((a, b) => a + b);
    for (var k = 0; k < kernel.length; k++) {
      kernel[k] /= norm;
    }
    return [
      for (var i = 0; i < x.length; i++)
        () {
          var s = 0.0;
          for (var k = 0; k < kernel.length; k++) {
            s += x[_reflectIncluding(i + k - radius, x.length)] * kernel[k];
          }
          return s;
        }(),
    ];
  }

  static List<double> gradient(List<double> x) {
    if (x.length <= 1) return const [];
    final n = x.length;
    return [
      x[1] - x[0],
      for (var i = 1; i < n - 1; i++) (x[i + 1] - x[i - 1]) / 2,
      x[n - 1] - x[n - 2],
    ];
  }

  static List<int> findPeaks(List<double> x, double height) => [
        for (var i = 1; i < x.length - 1; i++)
          if (x[i] > x[i - 1] && x[i] > x[i + 1] && x[i] >= height) i,
      ];

  /// Peaks by descending height, dropping any closer than [minDistance] to
  /// one already kept.
  static List<int> findProminentPeaks(List<double> x, int minDistance, double minProminence) {
    final candidates = [
      for (final p in findPeaks(x, 0)) if (prominence(p, x) >= minProminence) p,
    ]..sort((a, b) => x[b].compareTo(x[a]));
    final kept = <int>[];
    for (final p in candidates) {
      if (kept.every((k) => (k - p).abs() >= minDistance)) kept.add(p);
    }
    return kept..sort();
  }

  static double prominence(int peak, List<double> x) {
    if (peak < 0 || peak >= x.length) return 0;
    final h = x[peak];
    var leftMin = h;
    for (var i = peak - 1; i >= 0; i--) {
      leftMin = math.min(leftMin, x[i]);
      if (x[i] > h) break;
    }
    var rightMin = h;
    for (var i = peak + 1; i < x.length; i++) {
      rightMin = math.min(rightMin, x[i]);
      if (x[i] > h) break;
    }
    return h - math.max(leftMin, rightMin);
  }

  static double _crossing(List<double> x, int start, double level, int dir) {
    var i = start + dir;
    while (i >= 0 && i < x.length && x[i] > level) {
      start = i;
      i = start + dir;
    }
    if (i < 0 || i >= x.length) return start.toDouble();
    final a = x[start], b = x[i];
    if (a == b) return i.toDouble();
    return start + (level - a) / (b - a) * dir;
  }

  static List<(double, double)> peakWidths(List<double> x, List<int> peaks, double relHeight) => [
        for (final p in peaks)
          () {
            final level = x[p] - prominence(p, x) * relHeight;
            return (_crossing(x, p, level, -1), _crossing(x, p, level, 1));
          }(),
      ];

  static List<double> toProbabilities(List<double> out) =>
      out.any((v) => v < 0 || v > 1)
          ? [for (final v in out) 1 / (math.exp(-v) + 1)]
          : List.of(out);

  static List<double> resolveTimes(List<double> times, int count) =>
      times.length == count ? times : [for (var i = 0; i < count; i++) i * dt];

  static double? medianDelta(List<double> t) {
    final d = [for (var i = 1; i < t.length; i++) if (t[i] - t[i - 1] > 0) t[i] - t[i - 1]];
    if (d.isEmpty) return null;
    d.sort();
    return d[d.length ~/ 2];
  }

  static int nearestIndex(List<double> x, double target) {
    var best = 0;
    for (var i = 1; i < x.length; i++) {
      if ((x[i] - target).abs() < (x[best] - target).abs()) best = i;
    }
    return best;
  }

  static List<double> linspace(double a, double b, int n) =>
      n <= 1 ? [a] : [for (var i = 0; i < n; i++) (b - a) * i / (n - 1) + a];
}
