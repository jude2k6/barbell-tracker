import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../sensor/sensor_sample.dart';
import 'sensor_controller.dart';

/// One plotted sample: acceleration (g), quaternion, and the acceleration
/// rotated into the world frame (Stance's `DeviceStreamPlotPoint` and
/// `DeviceStreamGlobalPoint`).
class StreamPoint {
  const StreamPoint({
    required this.timeMs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.q0,
    required this.q1,
    required this.q2,
    required this.q3,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  factory StreamPoint.fromSample(SensorSample s) {
    final (gx, gy, gz) = globalAcceleration(s.ax, s.ay, s.az, s.q0, s.q1, s.q2, s.q3);
    return StreamPoint(
      timeMs: s.hostTimeUs ~/ 1000,
      ax: s.ax,
      ay: s.ay,
      az: s.az,
      q0: s.q0,
      q1: s.q1,
      q2: s.q2,
      q3: s.q3,
      gx: gx,
      gy: gy,
      gz: gz,
    );
  }

  final int timeMs;
  final double ax, ay, az;
  final double q0, q1, q2, q3;
  final double gx, gy, gz;
}

/// The acceleration vector rotated by the quaternion, as Stance computes it
/// (`DeviceStreamHeuristics.calculateGlobalAcceleration`). The quaternion is
/// used as given, without normalising.
(double, double, double) globalAcceleration(
  double ax,
  double ay,
  double az,
  double q0,
  double q1,
  double q2,
  double q3,
) {
  return (
    (1 - 2 * (q2 * q2 + q3 * q3)) * ax +
        2 * (q1 * q2 - q0 * q3) * ay +
        2 * (q1 * q3 + q0 * q2) * az,
    2 * (q1 * q2 + q0 * q3) * ax +
        (1 - 2 * (q3 * q3 + q1 * q1)) * ay +
        2 * (q2 * q3 - q0 * q1) * az,
    2 * (q1 * q3 - q0 * q2) * ax +
        2 * (q2 * q3 + q0 * q1) * ay +
        (1 - 2 * (q1 * q1 + q2 * q2)) * az,
  );
}

/// The three badges under Start/Stop (Stance's `DeviceStreamHeuristicState`).
class StreamHeuristics {
  const StreamHeuristics({
    this.stationary = false,
    this.calibrated = false,
    this.streamingIssue = false,
  });

  /// "Is Stationary".
  final bool stationary;

  /// False and stationary shows "Uncalibrated".
  final bool calibrated;

  /// "Streaming issue": one axis is still while another jumps.
  final bool streamingIssue;
}

/// Stance's once-a-second check over the last 10 plotted samples
/// (`evaluateAcceleration`).
StreamHeuristics evaluateStream(List<StreamPoint> last, StreamHeuristics previous) {
  if (last.length < 2) {
    return StreamHeuristics(
      calibrated: previous.calibrated,
      streamingIssue: previous.streamingIssue,
    );
  }
  final magnitudes = [
    for (final p in last) math.sqrt(p.ax * p.ax + p.ay * p.ay + p.az * p.az),
  ];
  var stable = true;
  for (var i = 1; i < magnitudes.length; i++) {
    if ((magnitudes[i] - magnitudes[i - 1]).abs() > 0.1) {
      stable = false;
      break;
    }
  }
  final n = last.length;
  // Calibrated and streaming issue are only re-judged while stationary;
  // otherwise the last verdict stays.
  if (!stable) {
    return StreamHeuristics(
      calibrated: previous.calibrated,
      streamingIssue: previous.streamingIssue,
    );
  }
  final meanZ = last.fold(0.0, (a, p) => a + p.az) / n;
  final meanX = last.fold(0.0, (a, p) => a + p.ax) / n;
  final meanY = last.fold(0.0, (a, p) => a + p.ay) / n;
  final calibrated =
      meanX.abs() <= 0.05 && meanY.abs() <= 0.05 && (meanZ - 1).abs() <= 0.05;
  var maxX = 0.0, maxY = 0.0, maxZ = 0.0;
  for (var i = 1; i < n; i++) {
    maxX = math.max(maxX, (last[i].ax - last[i - 1].ax).abs());
    maxY = math.max(maxY, (last[i].ay - last[i - 1].ay).abs());
    maxZ = math.max(maxZ, (last[i].az - last[i - 1].az).abs());
  }
  final stillX = maxX < 0.05, stillY = maxY < 0.05, stillZ = maxZ < 0.05;
  final movedX = maxX > 0.1, movedY = maxY > 0.1, movedZ = maxZ > 0.1;
  final issue = (stillX && (movedY || movedZ)) ||
      (stillY && (movedX || movedZ)) ||
      (stillZ && (movedX || movedY));
  return StreamHeuristics(stationary: true, calibrated: calibrated, streamingIssue: issue);
}

/// Indices that pick [maxPoints] evenly spread samples out of [size]
/// (Stance's `downsampleIndices`).
List<int> downsampleIndices(int size, int maxPoints) {
  if (size <= maxPoints) return [for (var i = 0; i < size; i++) i];
  final last = size - 1;
  final step = last / (maxPoints - 1);
  return [for (var i = 0; i < maxPoints; i++) (i * step).floor().clamp(0, last)];
}

/// The Device Stream screen's state (Stance's `DeviceStreamViewModel`).
///
/// Between [start] and [stop] every sample from the sensor is added to
/// [points]; they pile up until [clear]. Listeners are told at most every
/// 66 ms, and the badges are re-judged once a second from the last 10
/// points. Losing the sensor stops the stream.
///
/// Deviation: Stance's Start also switches the sensor's data stream on; the
/// sensor here always streams while connected, so Start only starts
/// collecting.
class DeviceStreamController extends ChangeNotifier {
  DeviceStreamController(this.sensor) {
    sensor.addListener(_onSensor);
  }

  static const uiThrottle = Duration(milliseconds: 66);
  static const heuristicInterval = Duration(seconds: 1);
  static const heuristicWindow = 10;

  final SensorController sensor;

  final List<StreamPoint> points = [];
  StreamHeuristics heuristics = const StreamHeuristics();
  bool streaming = false;

  StreamSubscription<SensorSample>? _sub;
  Timer? _heuristicTimer;
  Timer? _publishTimer;
  bool _disposed = false;

  bool get connected => sensor.isStreaming;
  bool get canStart => connected && !streaming;
  bool get canStop => connected && streaming;

  bool start() {
    if (!canStart) return false;
    streaming = true;
    _sub = sensor.samples.listen((s) {
      points.add(StreamPoint.fromSample(s));
      _schedulePublish();
    });
    _heuristicTimer = Timer.periodic(heuristicInterval, (_) {
      final from = math.max(0, points.length - heuristicWindow);
      heuristics = evaluateStream(points.sublist(from), heuristics);
      _publish();
    });
    _publish();
    return true;
  }

  void stop() {
    if (!streaming) return;
    streaming = false;
    _sub?.cancel();
    _sub = null;
    _heuristicTimer?.cancel();
    _heuristicTimer = null;
    _publish();
  }

  void clear() {
    points.clear();
    _publish();
  }

  void _onSensor() {
    if (!sensor.isStreaming && streaming) stop();
    _publish();
  }

  void _schedulePublish() {
    _publishTimer ??= Timer(uiThrottle, _publish);
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
    _heuristicTimer?.cancel();
    _publishTimer?.cancel();
    super.dispose();
  }
}
