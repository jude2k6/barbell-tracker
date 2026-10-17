import 'package:barbell_app/workout/device_stream.dart';
import 'package:barbell_app/workout/sensor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sensor_link.dart';

StreamPoint pt(double ax, double ay, double az) => StreamPoint(
    timeMs: 0, ax: ax, ay: ay, az: az, q0: 1, q1: 0, q2: 0, q3: 0, gx: 0, gy: 0, gz: 0);

void main() {
  test('global acceleration with the identity quaternion is unchanged', () {
    expect(globalAcceleration(0.1, 0.2, 0.9, 1, 0, 0, 0), (0.1, 0.2, 0.9));
  });

  test('90 degrees about x turns y into z', () {
    const h = 0.7071067811865476;
    final (x, y, z) = globalAcceleration(0, 1, 0, h, h, 0, 0);
    expect(x, closeTo(0, 1e-9));
    expect(y, closeTo(0, 1e-9));
    expect(z, closeTo(1, 1e-9));
  });

  group('evaluateStream', () {
    const none = StreamHeuristics();

    test('flat and still is stationary and calibrated', () {
      final h = evaluateStream([for (var i = 0; i < 10; i++) pt(0.01, -0.02, 1.0)], none);
      expect(h.stationary, isTrue);
      expect(h.calibrated, isTrue);
      expect(h.streamingIssue, isFalse);
    });

    test('still but tilted is uncalibrated', () {
      final h = evaluateStream([for (var i = 0; i < 10; i++) pt(0.3, 0, 0.95)], none);
      expect(h.stationary, isTrue);
      expect(h.calibrated, isFalse);
    });

    test('moving clears stationary but keeps the last verdicts', () {
      const before = StreamHeuristics(stationary: true, calibrated: true);
      final h = evaluateStream(
          [pt(0, 0, 1), pt(0, 0, 1.5), pt(0, 0, 0.9)], before);
      expect(h.stationary, isFalse);
      expect(h.calibrated, isTrue);
    });

    test('one frozen axis while another jumps is a streaming issue', () {
      // Magnitude stays within 0.1 per step, so it still counts as stationary.
      final h = evaluateStream([pt(0, 0, 1), pt(0, 0.15, 1), pt(0, 0, 1)], none);
      expect(h.stationary, isTrue);
      expect(h.streamingIssue, isTrue);
      final ok = evaluateStream([pt(0, 0, 1), pt(0, 0.04, 1), pt(0, 0, 1)], none);
      expect(ok.streamingIssue, isFalse);
    });

    test('fewer than two points: not stationary, verdicts kept', () {
      const before = StreamHeuristics(stationary: true, calibrated: true);
      final h = evaluateStream([pt(0, 0, 1)], before);
      expect(h.stationary, isFalse);
      expect(h.calibrated, isTrue);
    });
  });

  test('downsampleIndices spreads points evenly and keeps both ends', () {
    expect(downsampleIndices(3, 5), [0, 1, 2]);
    final idx = downsampleIndices(5000, 1000);
    expect(idx.length, 1000);
    expect(idx.first, 0);
    expect(idx.last, 4999);
  });

  test('controller collects between Start and Stop, and Clear empties', () async {
    final sensor = SensorController();
    final link = FakeSensorLink();
    final stream = DeviceStreamController(sensor);
    addTearDown(() {
      stream.dispose();
      sensor.dispose();
    });
    expect(stream.canStart, isFalse);
    await sensor.connect(link);
    expect(stream.canStart, isTrue);
    expect(stream.start(), isTrue);
    expect(stream.canStop, isTrue);
    link.emit(1);
    link.emit(2);
    await Future<void>.delayed(Duration.zero);
    expect(stream.points.length, 2);
    stream.stop();
    link.emit(3);
    await Future<void>.delayed(Duration.zero);
    expect(stream.points.length, 2);
    stream.clear();
    expect(stream.points, isEmpty);
  });

  test('losing the sensor stops the stream', () async {
    final sensor = SensorController(reconnectDelays: const []);
    final link = FakeSensorLink();
    final stream = DeviceStreamController(sensor);
    addTearDown(() {
      stream.dispose();
      sensor.dispose();
    });
    await sensor.connect(link);
    stream.start();
    link.drop();
    expect(stream.streaming, isFalse);
  });
}

