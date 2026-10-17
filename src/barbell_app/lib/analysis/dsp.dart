/// Signal-processing primitives with MATLAB semantics, so the ported
/// pipeline behaves like the MATLAB Coder library in the reference app.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------- complex

class _C {
  const _C(this.re, [this.im = 0]);
  final double re, im;
  _C operator +(_C o) => _C(re + o.re, im + o.im);
  _C operator -(_C o) => _C(re - o.re, im - o.im);
  _C operator *(_C o) => _C(re * o.re - im * o.im, re * o.im + im * o.re);
  _C operator /(_C o) {
    final d = o.re * o.re + o.im * o.im;
    return _C((re * o.re + im * o.im) / d, (im * o.re - re * o.im) / d);
  }

  _C operator -() => _C(-re, -im);
  _C scale(double k) => _C(re * k, im * k);
  _C sqrt() {
    final r = math.sqrt(re * re + im * im);
    final a = math.sqrt((r + re) / 2);
    final b = math.sqrt((r - re) / 2);
    return _C(a, im < 0 ? -b : b);
  }
}

// ------------------------------------------------------------ filter design

/// IIR filter coefficients, `a[0] == 1`.
class Iir {
  const Iir(this.b, this.a);
  final List<double> b, a;
}

/// Butterworth design equivalent to MATLAB `butter`.
///
/// [wn] is normalised to Nyquist (0–1): one value for 'low'/'high', two for
/// 'bandpass' (in which case the result has order `2 * n`).
Iir butter(int n, List<double> wn, {required String type}) {
  // Analog prototype poles on the unit circle, left half-plane.
  var p = [
    for (var k = 1; k <= n; k++)
      _C(math.cos(math.pi * (2 * k + n - 1) / (2 * n)),
          math.sin(math.pi * (2 * k + n - 1) / (2 * n))),
  ];
  var z = <_C>[];
  var gain = 1.0;

  // Pre-warp for the bilinear transform at fs = 2.
  const fs = 2.0;
  final warped = [for (final w in wn) 2 * fs * math.tan(math.pi * w / fs)];

  switch (type) {
    case 'low':
      final wo = warped.single;
      p = [for (final x in p) x.scale(wo)];
      gain *= math.pow(wo, n).toDouble();
    case 'high':
      final wo = warped.single;
      var prodNegP = const _C(1);
      for (final x in p) {
        prodNegP = prodNegP * (-x);
      }
      gain *= (const _C(1) / prodNegP).re;
      p = [for (final x in p) _C(wo) / x];
      z = List.filled(n, const _C(0));
    case 'bandpass':
      final bw = warped[1] - warped[0];
      final wo = math.sqrt(warped[0] * warped[1]);
      final scaled = [for (final x in p) x.scale(bw / 2)];
      p = [
        for (final x in scaled) x + (x * x - _C(wo * wo)).sqrt(),
        for (final x in scaled) x - (x * x - _C(wo * wo)).sqrt(),
      ];
      z = List.filled(n, const _C(0));
      gain *= math.pow(bw, n).toDouble();
    default:
      throw ArgumentError('unsupported filter type $type');
  }

  // Bilinear transform.
  const fs2 = 2 * fs;
  var num = const _C(1), den = const _C(1);
  for (final x in z) {
    num = num * (const _C(fs2) - x);
  }
  for (final x in p) {
    den = den * (const _C(fs2) - x);
  }
  final zd = [
    for (final x in z) (const _C(fs2) + x) / (const _C(fs2) - x),
    for (var i = 0; i < p.length - z.length; i++) const _C(-1),
  ];
  final pd = [for (final x in p) (const _C(fs2) + x) / (const _C(fs2) - x)];
  gain *= (num / den).re;

  final b = [for (final c in _poly(zd)) c * gain];
  final a = _poly(pd);
  return Iir(b, a);
}

List<double> _poly(List<_C> roots) {
  var c = <_C>[const _C(1)];
  for (final r in roots) {
    final next = List<_C>.filled(c.length + 1, const _C(0));
    for (var i = 0; i < c.length; i++) {
      next[i] = next[i] + c[i];
      next[i + 1] = next[i + 1] - c[i] * r;
    }
    c = next;
  }
  return [for (final x in c) x.re];
}

// ---------------------------------------------------------------- filtering

/// Direct-form II transposed filter (MATLAB `filter`), optional initial
/// state. Assumes `a[0] == 1` and `b.length == a.length`.
List<double> lfilter(Iir f, List<double> x, [List<double>? zi]) {
  final n = f.a.length;
  final z = List<double>.of(zi ?? List.filled(n - 1, 0.0));
  final y = List<double>.filled(x.length, 0);
  for (var i = 0; i < x.length; i++) {
    final xi = x[i];
    final yi = f.b[0] * xi + (n > 1 ? z[0] : 0);
    for (var k = 0; k < n - 2; k++) {
      z[k] = f.b[k + 1] * xi + z[k + 1] - f.a[k + 1] * yi;
    }
    if (n > 1) z[n - 2] = f.b[n - 1] * xi - f.a[n - 1] * yi;
    y[i] = yi;
  }
  return y;
}

/// Steady-state initial conditions for a unit step (MATLAB filtfilt's
/// sparse solve, scipy's `lfilter_zi`).
List<double> lfilterZi(Iir f) {
  final n = f.a.length - 1;
  // (I - A^T) zi = B, with A the companion matrix of a.
  final m = List.generate(n, (_) => List<double>.filled(n, 0));
  for (var i = 0; i < n; i++) {
    m[i][i] = 1;
  }
  for (var i = 0; i < n; i++) {
    m[i][0] += f.a[i + 1];
  }
  for (var i = 0; i < n - 1; i++) {
    m[i][i + 1] -= 1;
  }
  final rhs = [for (var i = 0; i < n; i++) f.b[i + 1] - f.a[i + 1] * f.b[0]];
  return _solve(m, rhs);
}

List<double> _solve(List<List<double>> m, List<double> rhs) {
  final n = rhs.length;
  final a = [for (var i = 0; i < n; i++) [...m[i], rhs[i]]];
  for (var c = 0; c < n; c++) {
    var piv = c;
    for (var r = c + 1; r < n; r++) {
      if (a[r][c].abs() > a[piv][c].abs()) piv = r;
    }
    final t = a[c];
    a[c] = a[piv];
    a[piv] = t;
    for (var r = 0; r < n; r++) {
      if (r == c) continue;
      final k = a[r][c] / a[c][c];
      for (var j = c; j <= n; j++) {
        a[r][j] -= k * a[c][j];
      }
    }
  }
  return [for (var i = 0; i < n; i++) a[i][n] / a[i][i]];
}

/// Zero-phase filtering with MATLAB `filtfilt` semantics: odd reflection
/// padding of `3 * (order)` samples and steady-state initial conditions.
List<double> filtfilt(Iir f, List<double> x) {
  final nfact = 3 * (f.a.length - 1);
  if (x.length <= nfact) {
    throw ArgumentError('signal too short for filtfilt (${x.length} <= $nfact)');
  }
  final zi = lfilterZi(f);
  final n = x.length;
  final ext = <double>[
    for (var i = nfact; i >= 1; i--) 2 * x[0] - x[i],
    ...x,
    for (var i = n - 2; i >= n - 1 - nfact; i--) 2 * x[n - 1] - x[i],
  ];
  var y = lfilter(f, ext, [for (final z in zi) z * ext.first]);
  y = y.reversed.toList();
  y = lfilter(f, y, [for (final z in zi) z * y.first]);
  y = y.reversed.toList();
  return y.sublist(nfact, nfact + n);
}

// ---------------------------------------------------------------- utilities

/// MATLAB `movmean(x, k)` with shrinking windows at the ends. Odd k is
/// centred; even k spans `k/2` samples back and `k/2 - 1` forward.
List<double> movmean(List<double> x, int k) {
  final n = x.length;
  final back = k ~/ 2;
  final fwd = k.isOdd ? back : back - 1;
  final prefix = List<double>.filled(n + 1, 0);
  for (var i = 0; i < n; i++) {
    prefix[i + 1] = prefix[i] + x[i];
  }
  return [
    for (var i = 0; i < n; i++)
      () {
        final lo = math.max(0, i - back), hi = math.min(n - 1, i + fwd);
        return (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1);
      }(),
  ];
}

double median(List<double> x) {
  if (x.isEmpty) return double.nan;
  final s = List<double>.of(x)..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// MATLAB `detrend(x)`: remove the least-squares straight line.
List<double> detrend(List<double> x) {
  final n = x.length;
  if (n < 2) return List.filled(n, 0);
  double st = 0, sy = 0, stt = 0, sty = 0;
  for (var i = 0; i < n; i++) {
    final t = i.toDouble();
    st += t;
    sy += x[i];
    stt += t * t;
    sty += t * x[i];
  }
  final slope = (n * sty - st * sy) / (n * stt - st * st);
  final icept = (sy - slope * st) / n;
  return [for (var i = 0; i < n; i++) x[i] - (icept + slope * i)];
}

/// MATLAB `cumtrapz(y)` with unit spacing.
List<double> cumtrapz(List<double> y) {
  final out = List<double>.filled(y.length, 0);
  for (var i = 1; i < y.length; i++) {
    out[i] = out[i - 1] + (y[i - 1] + y[i]) / 2;
  }
  return out;
}

List<double> linspace(double a, double b, int n) {
  if (n == 1) return [b];
  return [for (var i = 0; i < n; i++) a + (b - a) * i / (n - 1)];
}

/// MATLAB `interp1(x, y, xq)` (linear, NaN outside the range). [x] must be
/// strictly increasing.
List<double> interp1(List<double> x, List<double> y, List<double> xq) {
  final out = List<double>.filled(xq.length, double.nan);
  var j = 0;
  for (var i = 0; i < xq.length; i++) {
    final q = xq[i];
    if (q.isNaN || q < x.first || q > x.last) continue;
    if (q < x[j]) j = 0;
    while (j < x.length - 2 && x[j + 1] < q) {
      j++;
    }
    final x0 = x[j], x1 = x[j + 1];
    out[i] = x1 == x0 ? y[j] : y[j] + (y[j + 1] - y[j]) * (q - x0) / (x1 - x0);
  }
  return out;
}

double sum(Iterable<double> x) => x.fold(0.0, (a, b) => a + b);

double maxOf(Iterable<double> x) =>
    x.fold(double.negativeInfinity, (a, b) => b > a ? b : a);
