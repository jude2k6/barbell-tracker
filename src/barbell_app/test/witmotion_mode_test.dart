import 'dart:math' as math;
import 'dart:typed_data';

import 'package:barbell_app/sensor/orientation.dart';
import 'package:barbell_app/sensor/sensor_sample.dart';
import 'package:barbell_app/sensor/witmotion/witmotion_mode.dart';
import 'package:barbell_app/sensor/witmotion/witmotion_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

const _deg = math.pi / 180;

/// Accelerometer reading (g) of a still sensor at this roll and pitch.
(double, double, double) gravityAt(double rollDeg, double pitchDeg) => (
      -math.sin(pitchDeg * _deg),
      math.sin(rollDeg * _deg) * math.cos(pitchDeg * _deg),
      math.cos(rollDeg * _deg) * math.cos(pitchDeg * _deg),
    );

/// A decoded 20-byte frame with this accel/gyro and 6-byte tail.
WitImuFrame standard({
  (double, double, double) accel = (0, 0, 1),
  (double, double, double) gyro = (0, 0, 0),
  List<int> tail = const [0, 0, 0, 0, 0, 0],
}) =>
    WitImuFrame(
      ax: accel.$1, ay: accel.$2, az: accel.$3,
      gx: gyro.$1, gy: gyro.$2, gz: gyro.$3,
      tail: Uint8List.fromList(tail),
    );

List<int> anglesTail(double roll, double pitch, double yaw) {
  final d = ByteData(6);
  for (final (i, a) in [roll, pitch, yaw].indexed) {
    d.setInt16(2 * i, (a / 180 * 32768).round(), Endian.little);
  }
  return d.buffer.asUint8List();
}

List<int> clockTail(int ms) =>
    (ByteData(6)..setUint32(0, ms, Endian.little)).buffer.asUint8List();

void main() {
  group('eulerToQuaternion', () {
    test('a still sensor reads 1 g world-vertical at any roll, pitch, yaw', () {
      for (final (roll, pitch, yaw) in [
        (0.0, 0.0, 0.0), (30.0, -20.0, 50.0), (-120.0, 60.0, -170.0),
        (179.0, 5.0, 90.0),
      ]) {
        final (w, x, y, z) = eulerToQuaternion(roll, pitch, yaw);
        final (ax, ay, az) = gravityAt(roll, pitch);
        final s = SensorSample(
          hostTimeUs: 0, sensorTimeMs: null, ax: ax, ay: ay, az: az,
          gx: 0, gy: 0, gz: 0, q0: w, q1: x, q2: y, q3: z,
        );
        expect(s.worldZ, closeTo(1, 1e-9), reason: '$roll/$pitch/$yaw');
      }
    });
  });

  group('NotificationClock', () {
    test('spreads packed frames evenly between notifications', () {
      final c = NotificationClock();
      expect(c.stamp(8, 1000000), [
        for (var i = 7; i >= 0; i--) 1000000 - i * 5000,
      ]);
      expect(c.stamp(8, 1040000), [for (var i = 1; i <= 8; i++) 1000000 + i * 5000]);
    });

    test('a late notification leaves a hole instead of stretching', () {
      final c = NotificationClock()
        ..stamp(8, 0)
        ..stamp(8, 40000);
      final t = c.stamp(8, 120000); // one notification lost
      expect(t.last, 120000);
      expect(t.first, 120000 - 7 * 5000);
    });

    test('adapts to the rate actually delivered', () {
      final c = NotificationClock(); // assumes 200 Hz
      var t = <int>[];
      for (var i = 0; i < 10; i++) {
        t = c.stamp(1, i * 100000); // 10 Hz, one frame each
      }
      expect(t.single, 900000);
      final next = c.stamp(2, 1100000); // 2 frames over 200 ms: normal now
      expect(next, [1000000, 1100000]);
    });

    test('frames that arrive together still get increasing times', () {
      final c = NotificationClock()..stamp(1, 5000);
      final t = c.stamp(3, 5000);
      expect(t, [5001, 5002, 5003]);
      expect(c.stamp(1, 5000).single, greaterThan(5003));
    });
  });

  group('WitAnglesMode', () {
    test('turns the angles into the quaternion and spreads times', () {
      final mode = WitAnglesMode();
      final frames = [
        for (var i = 0; i < 4; i++)
          standard(accel: gravityAt(25, -10), tail: anglesTail(25, -10, 40)),
      ];
      final first = mode.samplesFrom(frames, 1000000);
      final second = mode.samplesFrom(frames, 1020000);
      expect(second.map((s) => s.hostTimeUs),
          [1005000, 1010000, 1015000, 1020000]);
      for (final s in [...first, ...second]) {
        expect(s.sensorTimeMs, isNull);
        expect(s.worldZ, closeTo(1, 1e-3));
      }
    });

    test('passes 30-byte frames through with their own clock and quaternion',
        () {
      final f = WitImuFrame(
        ax: 0, ay: 0, az: 1, gx: 0, gy: 0, gz: 0,
        chipTimeMs: 1234, quaternion: (1, 0, 0, 0),
      );
      final s = WitAnglesMode().samplesFrom([f], 99).single;
      expect(s.sensorTimeMs, 1234);
      expect(s.hostTimeUs, 99);
      expect(s.q0, 1);
    });

    test('sends 0x96 = 0 to make sure the angles are on', () {
      expect(WitAnglesMode().setupCommands, [WitCommands.outputAngles]);
    });
  });

  group('WitClockMode', () {
    test('uses the ms counter as sensor time', () {
      final mode = WitClockMode();
      final samples = mode.samplesFrom([
        for (final ms in [150894, 150899, 150904]) standard(tail: clockTail(ms)),
      ], 7);
      expect(samples.map((s) => s.sensorTimeMs), [150894, 150899, 150904]);
      expect(samples.every((s) => s.hostTimeUs == 7), isTrue);
      expect(mode.setupCommands, [WitCommands.outputClock]);
    });

    test('finds the tilt of a still sensor from the first sample', () {
      final mode = WitClockMode();
      final s = mode.samplesFrom(
          [standard(accel: gravityAt(40, 15), tail: clockTail(0))], 0).single;
      expect(s.worldZ, closeTo(1, 1e-9));
    });

    test('tracks a 90° roll from the gyro, with gravity agreeing', () {
      final mode = WitClockMode();
      late SensorSample last;
      for (var i = 0; i <= 200; i++) {
        final roll = 90.0 * i / 200; // 90°/s for 1 s at 200 Hz
        last = mode.samplesFrom([
          standard(
            accel: gravityAt(roll, 0),
            gyro: (90, 0, 0),
            tail: clockTail(i * 5),
          ),
        ], 0).single;
      }
      final (w, x, y, z) = eulerToQuaternion(90, 0, 0);
      final dot = (last.q0 * w + last.q1 * x + last.q2 * y + last.q3 * z).abs();
      expect(dot, closeTo(1, 1e-3));
      expect(last.worldZ, closeTo(1, 1e-3));
    });

    test('ignores the accelerometer while the bar accelerates', () {
      final mode = WitClockMode();
      mode.samplesFrom(
          [standard(accel: gravityAt(20, 0), tail: clockTail(0))], 0);
      late SensorSample s;
      for (var i = 1; i <= 100; i++) {
        // Still in rotation but pushed sideways and up: |a| ≈ 1.26 g, which
        // would drag the tilt toward the wrong "down" if trusted.
        s = mode.samplesFrom(
            [standard(accel: (0.4, 0.4, 1.1), tail: clockTail(i * 5))], 0).single;
      }
      final (w, x, y, z) = eulerToQuaternion(20, 0, 0);
      expect((s.q0 * w + s.q1 * x + s.q2 * y + s.q3 * z).abs(), closeTo(1, 1e-9));
    });
  });
}
