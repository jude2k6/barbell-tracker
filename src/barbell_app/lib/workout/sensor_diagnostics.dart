import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../sensor/orientation.dart';
import '../sensor/sensor_sample.dart';
import '../sensor/witmotion/witmotion_link.dart';
import '../sensor/witmotion/witmotion_mode.dart';
import '../sensor/witmotion/witmotion_stats.dart';
import 'file_log.dart';
import 'sensor_controller.dart';

/// One movement (a rep, or picking the bar up) as seen by [TiltComparison].
@immutable
class MovementResult {
  const MovementResult({
    required this.durationS,
    required this.peakTiltDiffDeg,
    required this.endTiltDiffDeg,
    required this.peakVelocity,
    required this.peakVelocityError,
    required this.peakDisplacementError,
  });

  final double durationS;

  /// Largest and final tilt difference between the reference and the app's
  /// filter, in degrees. Null without a reference.
  final double? peakTiltDiffDeg, endTiltDiffDeg;

  /// Largest vertical velocity (m/s) from the sample quaternions, integrated
  /// from rest at the start of the movement.
  final double peakVelocity;

  /// Largest gap between that velocity (m/s) and displacement (m) and the
  /// same integrated with the app's filter. Null without a reference.
  final double? peakVelocityError, peakDisplacementError;
}

/// Runs the app's [TiltFilter] beside whatever orientation the samples carry
/// and measures how far apart they get, plus the sample timing.
///
/// In angles mode the samples carry the sensor's own fusion, so this is the
/// "same reps, both filters" test from notes/own-orientation-clock-mode.md
/// without recording twice. The filter's dt there comes from the rebuilt
/// host times, not the sensor clock. In clock mode the samples already come
/// from our filter: there is no reference ([hasReference] false), and only
/// the timing and the movement velocities mean anything.
class TiltComparison {
  TiltComparison({TiltGains gains = const TiltGains(), this.traceLength = 1200})
      : filter = TiltFilter(gains: gains),
        _traceTilt = Float64List(traceLength),
        _traceRef = Float64List(traceLength),
        _traceOwn = Float64List(traceLength);

  /// Thresholds for "the bar is moving": off 1 g by this much, or turning
  /// faster than [movingGyroDps].
  static const movingAccelG = 0.15;
  static const movingGyroDps = 30.0;

  /// A movement ends after this long still; shorter ones are dropped.
  static const settleS = 0.5;
  static const minMovementS = 0.3;
  static const keepMovements = 12;

  /// Counter steps above this go into the [gapStep] bucket.
  static const maxStepMs = 100;
  static const gapStep = -1;

  static const _g = 9.81;
  static const _smoothing = 0.02;

  /// Samples kept in the live traces (1200 = 6 s at 200 Hz).
  final int traceLength;

  final TiltFilter filter;
  bool hasReference = true;

  int samples = 0;

  /// Sensor counter steps in ms → count ([gapStep] for > [maxStepMs] or
  /// backwards). Empty when the samples carry no sensor clock.
  final Map<int, int> counterSteps = {};

  /// Current, and smoothed RMS while still, tilt difference in degrees.
  double tiltDiffDeg = 0;
  double stillRmsDeg = 0;

  /// Mean gyro reading while still (deg/s): the bias the filter has to hide.
  double biasX = 0, biasY = 0, biasZ = 0;

  /// Newest first.
  final List<MovementResult> movements = [];

  /// Duration of the movement in progress, null when still.
  double? get movingS => _moving ? _movingS : null;

  int? _lastMs;
  int? _lastHostUs;
  double _stillMeanSq = 0;
  bool _stillSeen = false;

  bool _moving = false;
  double _movingS = 0, _stillS = 0;
  double _vRef = 0, _vOwn = 0, _dRef = 0, _dOwn = 0;
  double _peakTilt = 0, _peakV = 0, _peakVErr = 0, _peakDErr = 0;

  final Float64List _traceTilt, _traceRef, _traceOwn;
  int _traceHead = 0, _traceCount = 0;

  void add(SensorSample s) {
    samples++;
    final dt = _dt(s);

    filter.update(
        ax: s.ax, ay: s.ay, az: s.az, gx: s.gx, gy: s.gy, gz: s.gz, dt: dt);
    final ref = (s.q0, s.q1, s.q2, s.q3);
    final own = (filter.q0, filter.q1, filter.q2, filter.q3);
    tiltDiffDeg = hasReference ? tiltDifferenceDeg(ref, own) : 0;
    final refZ = s.worldZ;
    final ownZ = SensorSample(
      hostTimeUs: s.hostTimeUs, sensorTimeMs: s.sensorTimeMs,
      ax: s.ax, ay: s.ay, az: s.az, gx: s.gx, gy: s.gy, gz: s.gz,
      q0: own.$1, q1: own.$2, q2: own.$3, q3: own.$4,
    ).worldZ;

    _traceTilt[_traceHead] = tiltDiffDeg;
    _traceRef[_traceHead] = refZ - 1;
    _traceOwn[_traceHead] = ownZ - 1;
    _traceHead = (_traceHead + 1) % traceLength;
    if (_traceCount < traceLength) _traceCount++;

    final norm = math.sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
    final turn = math.sqrt(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz);
    final movingNow =
        (norm - 1).abs() > movingAccelG || turn > movingGyroDps;

    if (!movingNow && !_moving) _addStill(s);

    if (movingNow && !_moving) {
      _moving = true;
      _movingS = _stillS = 0;
      _vRef = _vOwn = _dRef = _dOwn = 0;
      _peakTilt = _peakV = _peakVErr = _peakDErr = 0;
    }
    if (!_moving) return;

    _movingS += dt;
    _vRef += (refZ - 1) * _g * dt;
    _vOwn += (ownZ - 1) * _g * dt;
    _dRef += _vRef * dt;
    _dOwn += _vOwn * dt;
    _peakTilt = math.max(_peakTilt, tiltDiffDeg);
    _peakV = math.max(_peakV, _vRef.abs());
    _peakVErr = math.max(_peakVErr, (_vRef - _vOwn).abs());
    _peakDErr = math.max(_peakDErr, (_dRef - _dOwn).abs());

    _stillS = movingNow ? 0 : _stillS + dt;
    if (_stillS >= settleS) _endMovement();
  }

  /// Oldest first: tilt difference (deg), and world-Z acceleration minus 1 g
  /// from the samples and from the app's filter.
  ({List<double> tilt, List<double> ref, List<double> own}) traces() {
    List<double> read(Float64List ring) {
      final start = (_traceHead - _traceCount) % traceLength;
      return [
        for (var i = 0; i < _traceCount; i++) ring[(start + i) % traceLength],
      ];
    }

    return (tilt: read(_traceTilt), ref: read(_traceRef), own: read(_traceOwn));
  }

  void reset() {
    filter.reset();
    samples = 0;
    counterSteps.clear();
    tiltDiffDeg = stillRmsDeg = 0;
    biasX = biasY = biasZ = 0;
    movements.clear();
    _lastMs = _lastHostUs = null;
    _stillMeanSq = 0;
    _stillSeen = false;
    _moving = false;
    _traceHead = _traceCount = 0;
  }

  /// Seconds since the previous sample: the sensor counter when there is one
  /// (and records its step), else the host times; one 200 Hz period when
  /// neither gives a sane step.
  double _dt(SensorSample s) {
    double? dt;
    final ms = s.sensorTimeMs;
    if (ms != null) {
      final last = _lastMs;
      if (last != null) {
        final step = ms - last;
        final ok = step > 0 && step <= maxStepMs;
        counterSteps.update(ok ? step : gapStep, (n) => n + 1,
            ifAbsent: () => 1);
        if (ok) dt = step / 1000;
      }
      _lastMs = ms;
    }
    final lastUs = _lastHostUs;
    if (dt == null && lastUs != null) {
      final step = s.hostTimeUs - lastUs;
      if (step > 0 && step <= maxStepMs * 1000) dt = step / 1e6;
    }
    _lastHostUs = s.hostTimeUs;
    return dt ?? 1 / 200;
  }

  void _addStill(SensorSample s) {
    final a = _stillSeen ? _smoothing : 1.0;
    _stillSeen = true;
    _stillMeanSq += a * (tiltDiffDeg * tiltDiffDeg - _stillMeanSq);
    stillRmsDeg = math.sqrt(_stillMeanSq);
    biasX += a * (s.gx - biasX);
    biasY += a * (s.gy - biasY);
    biasZ += a * (s.gz - biasZ);
  }

  void _endMovement() {
    _moving = false;
    final duration = _movingS - _stillS;
    if (duration < minMovementS) return;
    final result = MovementResult(
      durationS: duration,
      peakTiltDiffDeg: hasReference ? _peakTilt : null,
      endTiltDiffDeg: hasReference ? tiltDiffDeg : null,
      peakVelocity: _peakV,
      peakVelocityError: hasReference ? _peakVErr : null,
      peakDisplacementError: hasReference ? _peakDErr : null,
    );
    movements.insert(0, result);
    if (movements.length > keepMovements) movements.removeLast();
    onMovement?.call(result);
  }

  /// Called when a movement ends.
  void Function(MovementResult)? onMovement;
}

/// The diagnostics screen's state: a [TiltComparison] fed from the shared
/// sensor, the link's per-notification [WitLinkStats], and rates measured
/// once a second. Logs each movement and a timing summary every 10 s, so a
/// shared debug log carries the numbers too.
class SensorDiagnostics extends ChangeNotifier {
  SensorDiagnostics(this.sensor, {TiltGains gains = const TiltGains()})
      : comparison = TiltComparison(gains: gains) {
    comparison.onMovement = _logMovement;
    sensor.addListener(_onSensor);
    _onSensor();
    _sub = sensor.samples.listen((s) {
      comparison.add(s);
      _publishTimer ??= Timer(_uiThrottle, _publish);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  static const _tag = 'Diagnostics';
  static const _uiThrottle = Duration(milliseconds: 100);
  static const _summaryEvery = 10;

  final SensorController sensor;
  final TiltComparison comparison;

  /// Over the last second.
  double notificationsPerS = 0, samplesPerS = 0;

  String? _modeName;
  int _lastNotifications = 0, _lastSamples = 0, _ticks = 0;
  StreamSubscription<SensorSample>? _sub;
  Timer? _tick;
  Timer? _publishTimer;
  bool _disposed = false;

  WitMotionLink? get _wit => switch (sensor.link) {
        final WitMotionLink l => l,
        _ => null,
      };

  /// Null when the link isn't a WitMotion sensor.
  WitLinkStats? get linkStats => _wit?.stats;

  /// 'angles', 'clock', or null when unknown.
  String? get modeName => _modeName;

  bool get clockMode => _wit?.mode is WitClockMode;

  /// False when no WitMotion sensor is connected, so [clockMode] says
  /// nothing about the setting.
  bool get hasWitLink => _wit != null;

  set gains(TiltGains g) {
    comparison.filter.gains = g;
    _publish();
  }

  void reset() {
    comparison.reset();
    linkStats?.reset();
    _lastNotifications = _lastSamples = 0;
    _publish();
  }

  void _onSensor() {
    final name = _wit?.mode.name;
    if (name != _modeName) {
      _modeName = name;
      comparison.hasReference = !clockMode;
      reset(); // what the numbers mean just changed
    }
    _publish();
  }

  void _onTick() {
    _onSensor();
    final stats = linkStats;
    final n = stats?.notifications ?? 0;
    notificationsPerS = math.max(0, n - _lastNotifications).toDouble();
    samplesPerS = math.max(0, comparison.samples - _lastSamples).toDouble();
    _lastNotifications = n;
    _lastSamples = comparison.samples;
    if (++_ticks % _summaryEvery == 0 && sensor.isStreaming) _logSummary();
    _publish();
  }

  void _logSummary() {
    final stats = linkStats;
    final gaps = stats?.gapsMs;
    String hist(Map<int, int> m) => (m.keys.toList()..sort())
        .map((k) => '${k == TiltComparison.gapStep ? 'gap' : k}:${m[k]}')
        .join(' ');
    AppLog.i(
      _tag,
      'mode=$_modeName notif/s=${notificationsPerS.toStringAsFixed(0)} '
      'samples/s=${samplesPerS.toStringAsFixed(0)} mtu=${stats?.mtu} '
      'bytes={${hist(stats?.notificationLengths ?? const {})}} '
      'frames/notif={${hist(stats?.framesPerNotification ?? const {})}} '
      'gapMs=${gaps == null ? '-' : '${gaps.mean.toStringAsFixed(1)}/'
          '${gaps.p95.toStringAsFixed(1)}/${gaps.max.toStringAsFixed(1)}'} '
      'counterSteps={${hist(comparison.counterSteps)}} '
      'stillTiltRms=${comparison.stillRmsDeg.toStringAsFixed(2)}deg '
      'gyroBias=${comparison.biasX.toStringAsFixed(2)},'
      '${comparison.biasY.toStringAsFixed(2)},'
      '${comparison.biasZ.toStringAsFixed(2)}dps '
      'gains=${comparison.filter.gains}',
    );
  }

  void _logMovement(MovementResult m) {
    String f(double? v, int digits) => v?.toStringAsFixed(digits) ?? '-';
    AppLog.i(
      _tag,
      'movement mode=$_modeName ${m.durationS.toStringAsFixed(2)}s '
      'peakTilt=${f(m.peakTiltDiffDeg, 1)}deg '
      'endTilt=${f(m.endTiltDiffDeg, 1)}deg '
      'vPeak=${m.peakVelocity.toStringAsFixed(2)}m/s '
      'vErr=${f(m.peakVelocityError, 3)}m/s '
      'dErr=${f(m.peakDisplacementError == null ? null : m.peakDisplacementError! * 100, 1)}cm '
      'gains=${comparison.filter.gains}',
    );
  }

  void _publish() {
    _publishTimer?.cancel();
    _publishTimer = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    sensor.removeListener(_onSensor);
    _sub?.cancel();
    _tick?.cancel();
    _publishTimer?.cancel();
    super.dispose();
  }
}
