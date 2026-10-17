/// Port of the reference app's MATLAB Coder library (`libalgorithms`):
/// `preprocessing_thilina_V4` + `postprocessing2`.
///
/// Section numbers refer to notes/android-apk-decompiled.md. Indices in
/// comments are MATLAB 1-based; code uses 0-based lists with `_at(i)`
/// helpers where the original logic is clearer 1-based.
library;

import 'dart:math' as math;

import 'dsp.dart';

/// Coefficients the native library hard-codes for the vertical band-pass:
/// `butter(4, [0.25 4]/50)`, i.e. correct only at 100 Hz (§8).
const _fixedVerticalBandpass = Iir(
  [
    0.00014412022407538452, 0, -0.0005764808963015381, 0,
    0.0008647213444523071, 0, -0.0005764808963015381, 0,
    0.00014412022407538452,
  ],
  [
    1, -7.370332381485367, 23.79578457254215, -43.95961643549418,
    50.82674996737485, -37.66476395739411, 17.470170337982,
    -4.637347231624153, 0.5393551282803056,
  ],
);

class PipelineOptions {
  const PipelineOptions({this.matchNativeVerticalBand = true});

  /// true: reproduce the native library exactly (fixed 100 Hz coefficients
  /// for the vertical gate's band-pass). false: design it from the
  /// measured rate like the horizontal axes.
  final bool matchNativeVerticalBand;
}

class Preprocessed {
  Preprocessed(this.vertical, this.horizontalX, this.horizontalY, this.fs);

  /// Velocities in m/s, uniformly resampled, same length as the input.
  final List<double> vertical, horizontalX, horizontalY;

  /// Mean sample rate from the timestamps (`meanFrequencyHz`).
  final double fs;
}

/// §8: world frame → gravity/offset removal → spike gate → integrate →
/// 5-second moving-average drift removal.
Preprocessed preprocess({
  required List<double> ax,
  required List<double> ay,
  required List<double> az,
  required List<double> q0,
  required List<double> q1,
  required List<double> q2,
  required List<double> q3,
  required List<double> timestampsMs,
  PipelineOptions options = const PipelineOptions(),
}) {
  final n = ax.length;
  final t = [for (final x in timestampsMs) x - timestampsMs.first];
  if (n < 2 || t.last <= 0) throw ArgumentError('recording too short');
  final fs = n / (t.last / 1000);

  // World-frame acceleration (MATLAB quat2rotm normalises the quaternion).
  final wx = List<double>.filled(n, 0);
  final wy = List<double>.filled(n, 0);
  final wz = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final m = math.sqrt(q0[i] * q0[i] + q1[i] * q1[i] + q2[i] * q2[i] + q3[i] * q3[i]);
    final w = q0[i] / m, x = q1[i] / m, y = q2[i] / m, z = q3[i] / m;
    final a = ax[i], b = ay[i], c = az[i];
    wx[i] = (1 - 2 * (y * y + z * z)) * a + 2 * (x * y - w * z) * b + 2 * (x * z + w * y) * c;
    wy[i] = 2 * (x * y + w * z) * a + (1 - 2 * (x * x + z * z)) * b + 2 * (y * z - w * x) * c;
    wz[i] = 2 * (x * z - w * y) * a + 2 * (y * z + w * x) * b + (1 - 2 * (x * x + y * y)) * c;
  }

  List<double> centre(List<double> s) {
    final m = median(s);
    return detrend([for (final v in s) v - m]);
  }

  final vertA = centre([for (final v in wz) v - 1.0]);
  final horzX = centre(wx);
  final horzY = centre(wy);

  final nyq = fs / 2;
  if (10 / nyq >= 1) throw ArgumentError('sample rate too low (${fs.toStringAsFixed(1)} Hz)');
  final hp = butter(6, [10 / nyq], type: 'high');
  final bpRuntime = butter(4, [0.25 / nyq, 4 / nyq], type: 'bandpass');
  final bpVertical = options.matchNativeVerticalBand ? _fixedVerticalBandpass : bpRuntime;

  _spikeGate(vertA, hp, bpVertical);
  _spikeGate(horzX, hp, bpRuntime);
  _spikeGate(horzY, hp, bpRuntime);

  // Resample onto a uniform grid, integrate, remove drift, convert units.
  final (tu, keep) = _strictlyIncreasing(t);
  final grid = linspace(tu.first, tu.last, n);
  final w = fs.round();
  List<double> velocity(List<double> a) {
    final resampled = interp1(tu, [for (final i in keep) a[i]], grid);
    final integral = cumtrapz(resampled);
    final trend = movmean(integral, 5 * w);
    final scale = fs / 9.81;
    return [for (var i = 0; i < n; i++) (integral[i] - trend[i]) / scale];
  }

  return Preprocessed(velocity(vertA), velocity(horzX), velocity(horzY), fs);
}

/// Zero acceleration where >10 Hz content outweighs the 0.25–4 Hz band by
/// more than 0.1 g (smoothed over 9 samples), plus the two neighbours.
void _spikeGate(List<double> a, Iir hp, Iir bp) {
  final h = filtfilt(hp, a);
  final b = filtfilt(bp, a);
  final e = movmean([for (var i = 0; i < a.length; i++) h[i].abs() - b[i].abs()], 9);
  for (var m = 1; m < a.length - 1; m++) {
    if (e[m] > 0.1) {
      a[m - 1] = 0;
      a[m] = 0;
      a[m + 1] = 0;
    }
  }
}

/// interp1 needs strictly increasing x; drop repeated timestamps.
(List<double>, List<int>) _strictlyIncreasing(List<double> t) {
  final xs = <double>[t.first];
  final idx = <int>[0];
  for (var i = 1; i < t.length; i++) {
    if (t[i] > xs.last) {
      xs.add(t[i]);
      idx.add(i);
    }
  }
  return (xs, idx);
}

// ------------------------------------------------------------- postprocess

class NativeRep {
  NativeRep({
    required this.start,
    required this.end,
    required this.startSec,
    required this.endSec,
    required this.meanVelocity,
    required this.peakVelocity,
    required this.rom,
    required this.profile,
  });

  /// 1-based sample indices of the concentric phase.
  final int start, end;
  final double startSec, endSec;
  final double meanVelocity, peakVelocity;
  final double? rom;
  final ProfileFeatures profile;
}

/// §7 outputs, in % of ROM (0 = not found).
class ProfileFeatures {
  const ProfileFeatures({
    this.fractionBelowHalf = 0,
    this.stickLen = 0,
    this.stickStart = 0,
    this.stickEnd = 0,
    this.lowStart = 0,
    this.lowEnd = 0,
    this.vMinPos = 0,
    this.midDecel = 0,
  });

  final double fractionBelowHalf;
  final int stickLen, stickStart, stickEnd, lowStart, lowEnd, vMinPos;
  final double midDecel;
}

class _Thresholds {
  const _Thresholds(this.hi, this.lo, this.sizeFraction);
  final double hi, lo, sizeFraction;
}

const _deadlift = _Thresholds(0.10, 0.07, 0.30);
const _squatBench = _Thresholds(0.06, 0.01, 0.40);

const deadliftRawValues = {
  'Deadlift (conventional)',
  'Deadlift (sumo)',
  'Deadlift (trap bar)',
  'Deadlift (stiff legged)',
};

/// §6: rep detection and per-rep metrics. [totalSec] is the recording span
/// (Kotlin passes `t_last * 1e9` ns, divided back inside).
List<NativeRep> postprocess({
  required List<double> v,
  required double fs,
  required double totalSec,
  required String exerciseRaw,
}) {
  final n = v.length;
  if (n < 1) return const [];
  final isDeadlift = deadliftRawValues.contains(exerciseRaw);
  final th = isDeadlift ? _deadlift : _squatBench;
  double at(int i) => v[i - 1]; // 1-based

  // Steps 1–2: hysteresis phases.
  var starts = <int>[], ends = <int>[];
  var i = 0;
  do {
    i++;
    if (i < n && th.hi < at(i)) {
      var s = 0;
      for (var u = i; u > 1; u--) {
        if (at(u - 1) < th.lo) {
          s = u;
          break;
        }
      }
      var e = n;
      for (var u = i + 1; u < n; u++) {
        if (at(u) < th.lo) {
          e = u;
          break;
        }
      }
      starts.add(s == 0 ? 1 : s);
      ends.add(e);
      i = e + 1;
    }
  } while (i < n);
  if (starts.isEmpty) return const [];

  final complete = [for (var k = 0; k < ends.length; k++) if (ends[k] != n) k];
  starts = _uniqueSorted([for (final k in complete) starts[k]]);
  ends = _uniqueSorted([for (final k in complete) ends[k]]);
  final count = math.min(starts.length, ends.length);

  double segSum(List<double> x, int a, int b) {
    if (b < a) return 0;
    var acc = 0.0;
    for (var j = a; j <= b; j++) {
      acc += x[j - 1];
    }
    return acc;
  }

  // Step 3: size filter.
  final sizes = [for (var k = 0; k < count; k++) segSum(v, starts[k], ends[k])];
  final maxSizeAll = sizes.fold(0.0, (a, b) => b > a ? b : a);
  final sizeThr = (sizes.isEmpty ? 0.0 : maxOf(sizes)) * th.sizeFraction;
  var keep = [for (var k = 0; k < count; k++) if (sizeThr < sizes[k]) k];
  var repStarts = [for (final k in keep) starts[k]];
  var repEnds = [for (final k in keep) ends[k]];

  // Step 4: require a preceding descent (squat/bench only).
  if (!isDeadlift && repStarts.isNotEmpty) {
    final vneg = [for (final x in v) x > 0.05 ? 0.0 : x];
    final descent = List<double>.filled(repStarts.length, 1.0);
    for (var k = 0; k < repStarts.length; k++) {
      final s = repStarts[k];
      if (k == 0) {
        descent[k] = s < 500
            ? segSum(vneg, 1, s < 1 ? 0 : s)
            : segSum(vneg, s - 499, s);
      } else {
        final prevEnd = repEnds[k - 1];
        if (prevEnd > 0 && prevEnd < s) descent[k] = segSum(vneg, prevEnd, s);
      }
    }
    final thr = math.max(maxSizeAll * -0.5, -5.0);
    keep = [for (var k = 0; k < repStarts.length; k++) if (!(thr < descent[k])) k];
    repStarts = [for (final k in keep) repStarts[k]];
    repEnds = [for (final k in keep) repEnds[k]];
  }

  // Step 6: per-rep outputs.
  final smoothed20 = movmean(v, 20);
  final reps = <NativeRep>[];
  for (var k = 0; k < repStarts.length; k++) {
    final s = repStarts[k], e = repEnds[k];
    final seg = e >= s ? v.sublist(s - 1, e) : <double>[];
    final peak = seg.isEmpty ? 0.0 : maxOf(seg);
    final mean = seg.isEmpty ? 0.0 : sum(seg) / seg.length;
    final bound = k == 0 ? 1 : repEnds[k - 1];
    final ecc = _eccentricStart(v, smoothed20, s, bound);
    reps.add(NativeRep(
      start: s,
      end: e,
      startSec: s / n * totalSec,
      endSec: e / n * totalSec,
      meanVelocity: mean,
      peakVelocity: peak,
      rom: _rom(v, ecc, e, fs),
      profile: _profileFeatures(seg, v, s),
    ));
  }
  return reps;
}

List<int> _uniqueSorted(List<int> x) => (x.toSet().toList()..sort());

/// §6 step 6: walk back from the concentric start to the start of the
/// descent, never past [bound] (previous rep's end, or 1).
int _eccentricStart(List<double> v, List<double> smoothed, int s, int bound) {
  double at(int i) => v[i - 1];
  if (s <= 6) return 2;
  var d77 = s - 5, d98 = d77;
  do {
    d98 = d77;
    if (at(d98) <= -0.1) break;
    d77 = d98 - 1;
  } while (bound < d77);
  do {
    d77 = d98;
    if (at(d77) >= -0.03) break;
    d98 = d77 - 1;
  } while (bound < d98);
  // Smoothed velocity still falling (going backwards) and negative.
  final upto = d77;
  if (upto < 2) return d98;
  final dsm = [for (var j = 0; j < upto - 1; j++) smoothed[j + 1] - smoothed[j]];
  var cur = d77;
  while (true) {
    d98 = cur;
    cur = d98 - 1;
    if (cur < 1 || cur > dsm.length) break;
    if (dsm[cur - 1] >= 0 || at(cur) >= 0) break;
    if (cur == bound) break;
  }
  return d98;
}

/// §6 ROM: integrate raw velocity from the eccentric start to the rep end;
/// ROM = final position − position just after the lowest point.
double? _rom(List<double> v, int from, int to, double fs) {
  if (to < from || from < 1) return null;
  final pos = [for (final x in cumtrapz(v.sublist(from - 1, to))) x / fs];
  var minIdx = 0;
  for (var j = 1; j < pos.length; j++) {
    if (pos[j] < pos[minIdx]) minIdx = j;
  }
  final after = math.min(minIdx + 1, pos.length - 1); // native reads min+1
  return pos.last - pos[after];
}

/// §7: velocity-vs-displacement profile and the sticking-region state machine.
ProfileFeatures _profileFeatures(List<double> seg, List<double> v, int s) {
  if (seg.length < 2) return const ProfileFeatures();
  final d = <double>[];
  var acc = 0.0;
  for (final x in seg) {
    acc += x;
    d.add(acc);
  }
  final total = d.last;
  if (!(total > 0)) return const ProfileFeatures();

  // unique(d): sorted values, first occurrence index.
  final firstIdx = <double, int>{};
  for (var j = 0; j < d.length; j++) {
    firstIdx.putIfAbsent(d[j], () => j);
  }
  final xs = firstIdx.keys.toList()..sort();
  final ys = [for (final x in xs) seg[firstIdx[x]!]];
  if (xs.length < 2) return const ProfileFeatures();
  final grid = [for (var j = 1; j <= 100; j++) j * total / 100];
  final p = interp1(xs, ys, grid);

  final pMax = maxOf(p.where((x) => !x.isNaN));
  final fractionBelowHalf =
      p.where((x) => x < pMax * 0.5).length / 100.0;

  final dp = movmean([for (var j = 0; j < p.length - 1; j++) p[j + 1] - p[j]], 5);
  final dc = [for (final x in dp) x > 0 ? 0.0 : (x < 0 ? -1.0 : x)];
  final ps = movmean(p, 5);
  final nRep = seg.length;

  var triggered = false, stickEndFound = false, minFound = false;
  var phase = 0, low = 0, cb8 = -1;
  var hi = 0.0, lo = 0.0;
  var stickLen = 0, lowStart = 0, stickStart = 0, stickEnd = 0;
  var vMinPos = 0, lowEnd = 0;
  var midDecel = 0.0;

  for (var j = 0; j < dc.length; j++) {
    var b74 = false;
    var gotoB = false;
    if (!triggered) {
      if (dc[j] == -1) {
        cb8 = j;
        // roundsd imm 0b1010 in the native code = round toward +inf.
        final l = math.min(((j + 2) / 100 * nRep).ceilToDouble() + 10, nRep.toDouble()).toInt();
        final window = v.sublist(s - 1, math.min(v.length, s - 1 + math.max(l, 0)));
        final m = window.isEmpty ? 0.0 : maxOf(window);
        hi = 0.75 * m;
        lo = 0.325 * m;
        triggered = true;
      } else {
        continue; // b74 false → nothing at C
      }
    }
    // T:
    if (phase == 0) {
      if (ps[j] >= hi) continue;
      stickStart = j + 1;
      phase = 1;
    }
    b74 = phase == 1;
    if (b74 && low == 0 && !stickEndFound) {
      if (ps[j] < lo) {
        lowStart = j + 1;
        low = 1;
      }
    }
    gotoB = b74;
    if (gotoB) {
      // B:
      if (!minFound) {
        if (dc[j] == 0) {
          vMinPos = j + 1;
          midDecel = (cb8 + j + 2) * 0.5;
          minFound = true;
        } else {
          continue; // native: bVar29 = false, then next sample
        }
      }
    }
    // C:
    b74 = b74 && minFound;
    if (b74 && low == 1) {
      if (ps[j] <= lo && dc[j] != -1) continue;
      lowEnd = j + 1;
      low = 2;
    }
    if (b74 && !stickEndFound && low != 1) {
      if (ps[j] <= hi && dc[j] != -1) continue;
      stickEnd = j + 1;
      stickLen = stickEnd - stickStart;
      stickEndFound = true;
    }
  }
  if (stickEnd == 0) {
    stickStart = 0;
    lowStart = 0;
  }
  return ProfileFeatures(
    fractionBelowHalf: fractionBelowHalf,
    stickLen: stickLen,
    stickStart: stickStart,
    stickEnd: stickEnd,
    lowStart: lowStart,
    lowEnd: lowEnd,
    vMinPos: vMinPos,
    midDecel: midDecel,
  );
}
