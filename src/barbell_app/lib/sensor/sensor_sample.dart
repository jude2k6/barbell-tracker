import 'dart:math' as math;

/// One IMU sample as delivered by a barbell sensor.
///
/// Units match what the analysis pipeline expects: acceleration in g (sensor
/// frame, gravity included), angular rate in deg/s, and a unit quaternion
/// giving the sensor's orientation in the world frame.
class SensorSample {
  const SensorSample({
    required this.hostTimeUs,
    required this.sensorTimeMs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.q0,
    required this.q1,
    required this.q2,
    required this.q3,
  });

  /// Phone clock when the sample was decoded (microseconds since epoch).
  final int hostTimeUs;

  /// Sensor clock in milliseconds, or null if the sensor has no usable clock.
  /// For WitMotion this is the on-chip RTC (UTC epoch ms); for a DIY sensor
  /// it would be a monotonic counter.
  final int? sensorTimeMs;

  final double ax, ay, az;
  final double gx, gy, gz;

  /// Quaternion w, x, y, z.
  final double q0, q1, q2, q3;

  /// Vertical acceleration in g with gravity still included: the world-Z
  /// component of the accelerometer vector rotated by the quaternion.
  double get worldZ {
    final n = math.sqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3);
    if (n == 0) return 0;
    final w = q0 / n, x = q1 / n, y = q2 / n, z = q3 / n;
    // Third row of the rotation matrix built from (w, x, y, z).
    final r20 = 2 * (x * z - w * y);
    final r21 = 2 * (y * z + w * x);
    final r22 = 1 - 2 * (x * x + y * y);
    return r20 * ax + r21 * ay + r22 * az;
  }
}
