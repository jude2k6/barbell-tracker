/// Per-set IMU recording-quality metrics, a faithful port of Stance's
/// `ImuQualityMetricsCalculator` (notes §21).
///
/// Stance computes these once when a set is saved and stores them with the
/// set (and syncs and logs them). They carry no verdict and no thresholds,
/// and nothing in its UI reads them.
library;

import 'dart:math' as math;

import '../sensor/sensor_sample.dart';

/// Stance's `ImuQualityMetrics` (cloud copy: `RemoteImuQuality`).
class ImuQualityMetrics {
  const ImuQualityMetrics({
    required this.imuDataLossPct,
    required this.gyroSaturationDurationS,
    required this.accelSaturationDurationS,
    this.stillPeriodGlobalX,
    this.stillPeriodGlobalY,
    this.stillPeriodGlobalZ,
    this.stillPeriodStdGlobalX,
    this.stillPeriodStdGlobalY,
    this.stillPeriodStdGlobalZ,
    this.stillPeriodStdXPerPeriod = const [],
    this.stillPeriodStdYPerPeriod = const [],
    this.stillPeriodStdZPerPeriod = const [],
    required this.stillPeriodCount,
    required this.numberOfImpacts,
  });

  factory ImuQualityMetrics.fromJson(Map<String, dynamic> j) =>
      ImuQualityMetrics(
        imuDataLossPct: _d(j['imuDataLossPct']) ?? 0,
        gyroSaturationDurationS: _d(j['gyroSaturationDurationS']) ?? 0,
        accelSaturationDurationS: _d(j['accelSaturationDurationS']) ?? 0,
        stillPeriodGlobalX: _d(j['stillPeriodGlobalX']),
        stillPeriodGlobalY: _d(j['stillPeriodGlobalY']),
        stillPeriodGlobalZ: _d(j['stillPeriodGlobalZ']),
        stillPeriodStdGlobalX: _d(j['stillPeriodStdGlobalX']),
        stillPeriodStdGlobalY: _d(j['stillPeriodStdGlobalY']),
        stillPeriodStdGlobalZ: _d(j['stillPeriodStdGlobalZ']),
        stillPeriodStdXPerPeriod: _list(j['stillPeriodStdXPerPeriod']),
        stillPeriodStdYPerPeriod: _list(j['stillPeriodStdYPerPeriod']),
        stillPeriodStdZPerPeriod: _list(j['stillPeriodStdZPerPeriod']),
        stillPeriodCount: j['stillPeriodCount'] as int? ?? 0,
        numberOfImpacts: j['numberOfImpacts'] as int? ?? 0,
      );

  /// Time inside sensor-clock gaps longer than 1.5 sample intervals, in
  /// percent of the recording's span.
  final double imuDataLossPct;

  /// Samples with any axis beyond ±1999 deg/s, divided by the sample rate.
  final double gyroSaturationDurationS;

  /// Samples with any axis beyond ±15.9 g, divided by the sample rate.
  final double accelSaturationDurationS;

  /// Mean world-frame acceleration (g) over the still periods; null when
  /// there are none.
  final double? stillPeriodGlobalX, stillPeriodGlobalY, stillPeriodGlobalZ;

  /// Mean of the per-period standard deviations (2 Hz low-passed).
  final double? stillPeriodStdGlobalX,
      stillPeriodStdGlobalY,
      stillPeriodStdGlobalZ;

  final List<double> stillPeriodStdXPerPeriod,
      stillPeriodStdYPerPeriod,
      stillPeriodStdZPerPeriod;

  /// Still periods: |2 Hz high-passed |a|| < 0.02 g for at least 1 s.
  final int stillPeriodCount;

  /// Movement stretches (between ≥ 0.5 s settled spans) that peak above
  /// 2 g in the high-passed magnitude.
  final int numberOfImpacts;

  Map<String, dynamic> toJson() => {
        'imuDataLossPct': imuDataLossPct,
        'gyroSaturationDurationS': gyroSaturationDurationS,
        'accelSaturationDurationS': accelSaturationDurationS,
        if (stillPeriodGlobalX != null) 'stillPeriodGlobalX': stillPeriodGlobalX,
        if (stillPeriodGlobalY != null) 'stillPeriodGlobalY': stillPeriodGlobalY,
        if (stillPeriodGlobalZ != null) 'stillPeriodGlobalZ': stillPeriodGlobalZ,
        if (stillPeriodStdGlobalX != null)
          'stillPeriodStdGlobalX': stillPeriodStdGlobalX,
        if (stillPeriodStdGlobalY != null)
          'stillPeriodStdGlobalY': stillPeriodStdGlobalY,
        if (stillPeriodStdGlobalZ != null)
          'stillPeriodStdGlobalZ': stillPeriodStdGlobalZ,
        'stillPeriodStdXPerPeriod': stillPeriodStdXPerPeriod,
        'stillPeriodStdYPerPeriod': stillPeriodStdYPerPeriod,
        'stillPeriodStdZPerPeriod': stillPeriodStdZPerPeriod,
        'stillPeriodCount': stillPeriodCount,
        'numberOfImpacts': numberOfImpacts,
      };
}

// Stance's constants.
const _accelSatThreshold = 15.9; // g
const _gyroSatThreshold = 1999.0; // deg/s
const _gapMultiplier = 1.5;
const _hpfCutoff = 2.0; // Hz
const _lpfCutoff = 2.0; // Hz
const _filtfiltMinLength = 12;
const _stillThreshold = 0.02; // g
const _stillMinDuration = 1.0; // s
const _impactSettleThreshold = 0.25; // g
const _impactSettlePeriod = 0.5; // s
const _impactThreshold = 2.0; // g

/// Stance's `ImuQualityMetricsCalculator.compute`. Uses the sensor clock;
/// samples without one are skipped, as Stance skips samples whose chip time
/// doesn't parse. Null with fewer than two usable samples.
ImuQualityMetrics? computeImuQuality(List<SensorSample> samples) {
  if (samples.length < 2) return null;
  final t = <double>[];
  final acc = <List<double>>[];
  final gyro = <List<double>>[];
  final quat = <List<double>>[];
  int? t0;
  for (final s in samples) {
    final ms = s.sensorTimeMs;
    if (ms == null) continue;
    t0 ??= ms;
    t.add((ms - t0) / 1000);
    acc.add([s.ax, s.ay, s.az]);
    gyro.add([s.gx, s.gy, s.gz]);
    quat.add([s.q0, s.q1, s.q2, s.q3]);
  }
  if (t.length < 2) return null;

  final fs = _sampleRate(t);
  final dataLoss = _dataLoss(t, fs);
  final gyroSat = _saturation(gyro, _gyroSatThreshold, fs);
  final accelSat = _saturation(acc, _accelSatThreshold, fs);
  final mag = [
    for (final a in acc) math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]),
  ];
  final hpf = _highPass(_hpfCutoff, fs, mag);
  final still = _stillPeriods(hpf, fs);
  final impacts = _countImpacts(hpf, fs);
  if (still.isEmpty) {
    return ImuQualityMetrics(
      imuDataLossPct: dataLoss,
      gyroSaturationDurationS: gyroSat,
      accelSaturationDurationS: accelSat,
      stillPeriodCount: 0,
      numberOfImpacts: impacts,
    );
  }

  final global = _rotateToGlobal(acc, quat);
  final meanX = <double>[], meanY = <double>[], meanZ = <double>[];
  final stdX = <double>[], stdY = <double>[], stdZ = <double>[];
  for (final (start, end) in still) {
    if (start >= end || end > global.length) continue;
    final part = global.sublist(start, end);
    final x = [for (final v in part) v[0]];
    final y = [for (final v in part) v[1]];
    final z = [for (final v in part) v[2]];
    meanX.add(_mean(x));
    meanY.add(_mean(y));
    meanZ.add(_mean(z));
    final filter = x.length >= _filtfiltMinLength
        ? (List<double> v) => _butterworthFiltfilt(_lpfCutoff, fs, v)
        : (List<double> v) => v;
    stdX.add(_sampleStd(filter(x)));
    stdY.add(_sampleStd(filter(y)));
    stdZ.add(_sampleStd(filter(z)));
  }
  double? meanOrNull(List<double> v) => v.isEmpty ? null : _mean(v);
  return ImuQualityMetrics(
    imuDataLossPct: dataLoss,
    gyroSaturationDurationS: gyroSat,
    accelSaturationDurationS: accelSat,
    stillPeriodGlobalX: meanOrNull(meanX),
    stillPeriodGlobalY: meanOrNull(meanY),
    stillPeriodGlobalZ: meanOrNull(meanZ),
    stillPeriodStdGlobalX: meanOrNull(stdX),
    stillPeriodStdGlobalY: meanOrNull(stdY),
    stillPeriodStdGlobalZ: meanOrNull(stdZ),
    stillPeriodStdXPerPeriod: stdX,
    stillPeriodStdYPerPeriod: stdY,
    stillPeriodStdZPerPeriod: stdZ,
    // Counts every period found, even one skipped above (as Stance).
    stillPeriodCount: still.length,
    numberOfImpacts: impacts,
  );
}

/// 1 / median of the positive time steps; 100 Hz if there are none.
double _sampleRate(List<double> t) {
  final dts = [
    for (var i = 1; i < t.length; i++)
      if (t[i] - t[i - 1] > 0) t[i] - t[i - 1],
  ];
  return dts.isEmpty ? 100 : 1 / _median(dts);
}

double _dataLoss(List<double> t, double fs) {
  final limit = _gapMultiplier / fs;
  var lost = 0.0;
  for (var i = 1; i < t.length; i++) {
    final dt = t[i] - t[i - 1];
    if (dt > limit) lost += dt;
  }
  final span = t.last - t.first;
  return span <= 0 ? 0 : lost / span * 100;
}

double _saturation(List<List<double>> v, double limit, double fs) =>
    v.where((a) => a.any((x) => x.abs() > limit)).length / fs;

/// First-order RC high-pass, `y[0] = α·x[0]`.
List<double> _highPass(double f, double fs, List<double> x) {
  if (x.isEmpty) return x;
  final alpha = 1 / (f * 2 * math.pi * (1 / fs) + 1);
  final y = List<double>.filled(x.length, 0);
  y[0] = x[0] * alpha;
  for (var i = 1; i < x.length; i++) {
    y[i] = (y[i - 1] + x[i] - x[i - 1]) * alpha;
  }
  return y;
}

/// Runs where [inside] holds for at least [minS] seconds, as [start, end).
List<(int, int)> _runs(int n, bool Function(int) inside, double fs,
    double minS) {
  final out = <(int, int)>[];
  var open = false;
  var start = 0;
  for (var i = 0; i < n; i++) {
    final ins = inside(i);
    if (ins && !open) {
      start = i;
      open = true;
    } else if (!ins && open) {
      if ((i - start) / fs >= minS) out.add((start, i));
      open = false;
    }
  }
  if (open && (n - start) / fs >= minS) out.add((start, n));
  return out;
}

List<(int, int)> _stillPeriods(List<double> hpf, double fs) => _runs(
    hpf.length, (i) => hpf[i].abs() < _stillThreshold, fs, _stillMinDuration);

/// Splits the recording at settled spans (|hpf| < 0.25 g for ≥ 0.5 s) and
/// counts the remaining stretches whose hpf exceeds +2 g. Stance compares
/// the signed value, not the magnitude.
int _countImpacts(List<double> hpf, double fs) {
  final n = hpf.length;
  final settled = List<bool>.filled(n, false);
  for (final (a, b) in _runs(n, (i) => hpf[i].abs() < _impactSettleThreshold,
      fs, _impactSettlePeriod)) {
    for (var i = a; i < b; i++) {
      settled[i] = true;
    }
  }
  var count = 0;
  for (final (a, b) in _runs(n, (i) => !settled[i], fs, 0)) {
    if (hpf.sublist(a, b).any((v) => v > _impactThreshold)) count++;
  }
  return count;
}

/// Accelerometer vectors rotated into the world frame by the (unnormalised)
/// quaternion; zero vectors where the quaternion is zero.
List<List<double>> _rotateToGlobal(
    List<List<double>> acc, List<List<double>> quat) {
  final n = math.min(acc.length, quat.length);
  return [
    for (var i = 0; i < n; i++) _rotate(acc[i], quat[i]),
  ];
}

List<double> _rotate(List<double> a, List<double> q) {
  final w = q[0], x = q[1], y = q[2], z = q[3];
  if (w * w + x * x + y * y + z * z <= 0) return const [0, 0, 0];
  return [
    (1 - 2 * (y * y + z * z)) * a[0] +
        2 * (x * y - w * z) * a[1] +
        2 * (x * z + w * y) * a[2],
    2 * (x * y + w * z) * a[0] +
        (1 - 2 * (x * x + z * z)) * a[1] +
        2 * (y * z - w * x) * a[2],
    2 * (x * z - w * y) * a[0] +
        2 * (y * z + w * x) * a[1] +
        (1 - 2 * (x * x + y * y)) * a[2],
  ];
}

/// Zero-phase 4th-order Butterworth low-pass as two biquads (Q from
/// sin(π/8) and sin(3π/8)), forward then backward. The forward pass starts
/// from the first sample, the backward pass from the forward output's last.
List<double> _butterworthFiltfilt(double fc, double fs, List<double> x) {
  if (x.isEmpty) return x;
  final k = math.tan(math.pi * fc / fs);
  final s1 = _section(k, 1 / (2 * math.sin(math.pi / 8)));
  final s2 = _section(k, 1 / (2 * math.sin(3 * math.pi / 8)));
  final x0 = x.first;
  final fwd = _biquad(s2, _biquad(s1, x, x0), x0);
  final xn = fwd.isEmpty ? x0 : fwd.last;
  final back = _biquad(s1, _biquad(s2, fwd.reversed.toList(), xn), xn);
  return back.reversed.toList();
}

/// (b, a) of one low-pass biquad section.
(List<double>, List<double>) _section(double k, double q) {
  final k2 = k * k;
  final norm = k2 + k / q + 1;
  return (
    [k2 / norm, 2 * k2 / norm, k2 / norm],
    [1, 2 * (k2 - 1) / norm, (k2 - k / q + 1) / norm],
  );
}

/// Direct form II, state primed with the steady state for [initial].
List<double> _biquad(
    (List<double>, List<double>) coeffs, List<double> x, double initial) {
  final (b, a) = coeffs;
  final dc = a[1] + 1 + a[2];
  var w1 = dc != 0 ? initial / dc : 0.0;
  var w2 = w1;
  return [
    for (final v in x)
      () {
        final w = v - a[1] * w1 - a[2] * w2;
        final y = b[0] * w + b[1] * w1 + b[2] * w2;
        w2 = w1;
        w1 = w;
        return y;
      }(),
  ];
}

double _mean(List<double> v) =>
    v.isEmpty ? 0 : v.fold(0.0, (s, x) => s + x) / v.length;

double _sampleStd(List<double> v) {
  if (v.length <= 1) return 0;
  final m = _mean(v);
  final ss = v.fold(0.0, (s, x) => s + (x - m) * (x - m));
  return math.sqrt(ss / (v.length - 1));
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  final h = s.length ~/ 2;
  return s.length.isEven ? (s[h - 1] + s[h]) / 2 : s[h];
}

double? _d(Object? v) => (v as num?)?.toDouble();

List<double> _list(Object? v) =>
    [for (final x in (v as List? ?? const [])) (x as num).toDouble()];
