import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Unit quaternion (w, x, y, z) for roll/pitch/yaw in degrees, ZYX order
/// (yaw, then pitch, then roll), rotating the sensor frame into the world
/// frame like [SensorSample]'s quaternion. This is the convention WitMotion's
/// angles use: roll = atan2(ay, az), pitch = -asin(ax) when still.
(double, double, double, double) eulerToQuaternion(
    double rollDeg, double pitchDeg, double yawDeg) {
  const halfRad = math.pi / 360;
  final cr = math.cos(rollDeg * halfRad), sr = math.sin(rollDeg * halfRad);
  final cp = math.cos(pitchDeg * halfRad), sp = math.sin(pitchDeg * halfRad);
  final cy = math.cos(yawDeg * halfRad), sy = math.sin(yawDeg * halfRad);
  return (
    cr * cp * cy + sr * sp * sy,
    sr * cp * cy - cr * sp * sy,
    cr * sp * cy + sr * cp * sy,
    cr * cp * sy - sr * sp * cy,
  );
}

/// Angle in degrees between the world-vertical axes of two orientations
/// (unit quaternions w, x, y, z). Yaw differences don't count, so this is
/// the tilt error that matters for [SensorSample.worldZ].
double tiltDifferenceDeg((double, double, double, double) a,
    (double, double, double, double) b) {
  (double, double, double) up((double, double, double, double) q) {
    final (w, x, y, z) = q;
    return (2 * (x * z - w * y), 2 * (w * x + y * z), w * w - x * x - y * y + z * z);
  }

  final (ax, ay, az) = up(a);
  final (bx, by, bz) = up(b);
  final na = math.sqrt(ax * ax + ay * ay + az * az);
  final nb = math.sqrt(bx * bx + by * by + bz * bz);
  if (na == 0 || nb == 0) return 0;
  final cos = ((ax * bx + ay * by + az * bz) / (na * nb)).clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}

/// [TiltFilter] tuning. The defaults are textbook values, not yet tuned on
/// real lifts (notes/own-orientation-clock-mode.md).
@immutable
class TiltGains {
  const TiltGains({this.kp = 2.0, this.ki = 0.1, this.accelGate = 0.1});

  factory TiltGains.fromJson(Map<String, dynamic> j) {
    const d = TiltGains();
    double read(String k, double fallback) =>
        (j[k] as num?)?.toDouble() ?? fallback;
    return TiltGains(
      kp: read('kp', d.kp),
      ki: read('ki', d.ki),
      accelGate: read('accelGate', d.accelGate),
    );
  }

  /// Proportional and integral gains on the gravity error (rad/s per unit).
  final double kp, ki;

  /// Accelerometer corrections apply only while | |a| - 1 g | is below this.
  final double accelGate;

  TiltGains copyWith({double? kp, double? ki, double? accelGate}) => TiltGains(
        kp: kp ?? this.kp,
        ki: ki ?? this.ki,
        accelGate: accelGate ?? this.accelGate,
      );

  Map<String, dynamic> toJson() => {'kp': kp, 'ki': ki, 'accelGate': accelGate};

  @override
  bool operator ==(Object other) =>
      other is TiltGains &&
      other.kp == kp &&
      other.ki == ki &&
      other.accelGate == accelGate;

  @override
  int get hashCode => Object.hash(kp, ki, accelGate);

  @override
  String toString() => 'kp=$kp ki=$ki gate=${accelGate}g';
}

/// 6-axis Mahony filter: integrates the gyro and pulls the estimate toward
/// the accelerometer's gravity direction while the sensor is near 1 g.
///
/// Only tilt is observable without a magnetometer, so yaw drifts. That's
/// fine here: the analysis only uses the quaternion to find world-vertical.
class TiltFilter {
  TiltFilter({this.gains = const TiltGains()});

  /// Can be changed while running (the diagnostics screen tunes them live).
  TiltGains gains;

  double q0 = 1, q1 = 0, q2 = 0, q3 = 0;
  double _ix = 0, _iy = 0, _iz = 0;
  bool _initialised = false;

  /// Acceleration in g, angular rate in deg/s, [dt] in seconds. The first
  /// sample near 1 g sets the tilt directly.
  void update({
    required double ax, required double ay, required double az,
    required double gx, required double gy, required double gz,
    required double dt,
  }) {
    final norm = math.sqrt(ax * ax + ay * ay + az * az);
    final TiltGains(:kp, :ki, :accelGate) = gains;
    final nearOneG = norm > 0 && (norm - 1).abs() < accelGate;
    if (!_initialised) {
      if (!nearOneG) return;
      final roll = math.atan2(ay, az) * 180 / math.pi;
      final pitch =
          math.atan2(-ax, math.sqrt(ay * ay + az * az)) * 180 / math.pi;
      final (w, x, y, z) = eulerToQuaternion(roll, pitch, 0);
      q0 = w;
      q1 = x;
      q2 = y;
      q3 = z;
      _initialised = true;
      return;
    }
    const degToRad = math.pi / 180;
    var wx = gx * degToRad, wy = gy * degToRad, wz = gz * degToRad;
    if (nearOneG) {
      final nx = ax / norm, ny = ay / norm, nz = az / norm;
      // World up expressed in the sensor frame (third row of the rotation).
      final vx = 2 * (q1 * q3 - q0 * q2);
      final vy = 2 * (q0 * q1 + q2 * q3);
      final vz = q0 * q0 - q1 * q1 - q2 * q2 + q3 * q3;
      final ex = ny * vz - nz * vy;
      final ey = nz * vx - nx * vz;
      final ez = nx * vy - ny * vx;
      _ix += ki * ex * dt;
      _iy += ki * ey * dt;
      _iz += ki * ez * dt;
      wx += kp * ex + _ix;
      wy += kp * ey + _iy;
      wz += kp * ez + _iz;
    }
    final h = 0.5 * dt;
    final a = q0, b = q1, c = q2, d = q3;
    q0 = a + (-b * wx - c * wy - d * wz) * h;
    q1 = b + (a * wx + c * wz - d * wy) * h;
    q2 = c + (a * wy - b * wz + d * wx) * h;
    q3 = d + (a * wz + b * wy - c * wx) * h;
    final n = math.sqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3);
    q0 /= n;
    q1 /= n;
    q2 /= n;
    q3 /= n;
  }

  void reset() {
    q0 = 1;
    q1 = q2 = q3 = 0;
    _ix = _iy = _iz = 0;
    _initialised = false;
  }
}
