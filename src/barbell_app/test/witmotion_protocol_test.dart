import 'dart:typed_data';

import 'package:barbell_app/sensor/rate_monitor.dart';
import 'package:barbell_app/sensor/sensor_sample.dart';
import 'package:barbell_app/sensor/witmotion/witmotion_mode.dart';
import 'package:barbell_app/sensor/witmotion/witmotion_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a 0x61 frame the way a WitMotion sensor would send it.
List<int> imuFrame({
  int ms = 250,
  List<int> accelRaw = const [0, 0, 2048], // 1 g on Z
  List<int> gyroRaw = const [0, 0, 0],
  List<int> quatRaw = const [32767, 0, 0, 0], // identity
}) {
  final d = ByteData(30)
    ..setUint8(0, 0x55)
    ..setUint8(1, 0x61)
    ..setUint8(2, 26) // 2026
    ..setUint8(3, 10)
    ..setUint8(4, 12)
    ..setUint8(5, 14)
    ..setUint8(6, 30)
    ..setUint8(7, 5)
    ..setUint16(8, ms, Endian.little);
  for (var i = 0; i < 3; i++) {
    d.setInt16(10 + 2 * i, accelRaw[i], Endian.little);
    d.setInt16(16 + 2 * i, gyroRaw[i], Endian.little);
  }
  for (var i = 0; i < 4; i++) {
    d.setInt16(22 + 2 * i, quatRaw[i], Endian.little);
  }
  return d.buffer.asUint8List();
}

List<int> batteryFrame(int centivolts) {
  final d = ByteData(20)
    ..setUint8(0, 0x55)
    ..setUint8(1, 0x71)
    ..setUint8(2, 0x64)
    ..setInt16(4, centivolts, Endian.little);
  return d.buffer.asUint8List();
}

/// A stock 20-byte frame captured from a WT9011DCL lying flat:
/// accel ≈ (−0.01, −0.002, 1.006) g, roll −0.14°, pitch 0.63°.
const standardFrame = [
  0x55, 0x61, 0xea, 0xff, 0xfb, 0xff, 0x0d, 0x08, 0x01, 0x00, //
  0x00, 0x00, 0xff, 0xff, 0xe6, 0xff, 0x73, 0x00, 0x00, 0x00,
];

List<WitImuFrame> imuFrames(List<WitEvent> events) =>
    events.whereType<WitImuFrame>().toList();

void main() {
  group('WitFrameDecoder', () {
    test('decodes scaling, chip time and quaternion of a 30-byte frame', () {
      final decoder = WitFrameDecoder();
      final events = decoder.add([
        ...imuFrame(gyroRaw: [16384, 0, -16384]),
        ...imuFrame(),
      ]);
      expect(events, hasLength(2));
      expect(decoder.imuLength, 30);
      final s = extendedSample(events.first as WitImuFrame, 42);
      expect(s.hostTimeUs, 42);
      expect(s.az, closeTo(1.0, 1e-9)); // 2048 / 32768 * 16
      expect(s.gx, closeTo(1000.0, 1e-9));
      expect(s.gz, closeTo(-1000.0, 1e-9));
      expect(s.q0, closeTo(1.0, 1e-4));
      expect(s.worldZ, closeTo(1.0, 1e-6));
      expect(
        s.sensorTimeMs,
        DateTime.utc(2026, 10, 12, 14, 30, 5, 250).millisecondsSinceEpoch,
      );
    });

    test('decodes the stock 20-byte frame', () {
      final decoder = WitFrameDecoder();
      final frames = imuFrames(decoder.add([...standardFrame, ...standardFrame]));
      expect(frames, hasLength(2));
      expect(decoder.imuLength, 20);
      final f = frames.first;
      expect(f.isExtended, isFalse);
      expect(f.ax, closeTo(-22 / 32768 * 16, 1e-9));
      expect(f.az, closeTo(2061 / 32768 * 16, 1e-9));
      expect(f.gx, closeTo(1 / 32768 * 2000, 1e-9));
      expect(f.gz, closeTo(-1 / 32768 * 2000, 1e-9));
      expect(f.tail, [0xe6, 0xff, 0x73, 0x00, 0x00, 0x00]);
    });

    test('never reads a 20-byte stream as 30-byte frames', () {
      final decoder = WitFrameDecoder();
      final bytes = [for (var i = 0; i < 50; i++) ...standardFrame];
      expect(imuFrames(decoder.add(bytes)), hasLength(50));
      expect(decoder.skippedBytes, 0);
    });

    test('splits frames packed into one notification', () {
      final decoder = WitFrameDecoder()..add([...standardFrame, ...standardFrame]);
      final packed = [for (var i = 0; i < 8; i++) ...standardFrame];
      expect(imuFrames(decoder.add(packed)), hasLength(8));
    });

    test('waits for the next header before guessing the length', () {
      final decoder = WitFrameDecoder();
      expect(decoder.add(standardFrame), isEmpty);
      // Detected: the held frame and this one, then one per notification.
      expect(imuFrames(decoder.add(standardFrame)), hasLength(2));
      expect(imuFrames(decoder.add(standardFrame)), hasLength(1));
    });

    test('keeps register replies between 20-byte frames', () {
      final events = WitFrameDecoder().add(
          [...standardFrame, ...batteryFrame(380), ...standardFrame, ...standardFrame]);
      expect(events.whereType<WitBatteryEvent>(), hasLength(1));
      expect(imuFrames(events), hasLength(3));
    });

    test('reassembles frames split across notifications', () {
      final bytes = [...imuFrame(ms: 0), ...imuFrame(ms: 5)];
      final decoder = WitFrameDecoder();
      final events = <WitEvent>[
        ...decoder.add(bytes.sublist(0, 7)),
        ...decoder.add(bytes.sublist(7, 41)),
        ...decoder.add(bytes.sublist(41)),
      ];
      expect(events, hasLength(2));
    });

    test('resyncs after garbage and skips unknown frame types', () {
      final decoder = WitFrameDecoder();
      final events =
          decoder.add([0x00, 0x55, 0x00, 0x13, ...imuFrame(), ...imuFrame()]);
      expect(events, hasLength(2));
      expect(decoder.skippedBytes, 4);
    });

    test('detects the length again when the stream stops lining up', () {
      final decoder = WitFrameDecoder()..add([...standardFrame, ...standardFrame]);
      final events = decoder.add([
        ...standardFrame.sublist(0, 9), // a truncated frame
        ...imuFrame(), ...imuFrame(), ...imuFrame(),
      ]);
      // The truncated frame swallows the start of the first 30-byte one.
      expect(decoder.imuLength, 30);
      expect(imuFrames(events).where((f) => f.isExtended), hasLength(2));
    });

    test('parses battery register replies', () {
      final events = WitFrameDecoder().add(batteryFrame(380));
      final b = events.single as WitBatteryEvent;
      expect(b.volts, closeTo(3.80, 1e-9));
      expect(b.percent, 50);
    });

    test('battery table matches the reference app', () {
      expect(WitFrameDecoder.batteryPercent(4.10), 100);
      expect(WitFrameDecoder.batteryPercent(3.96), 90); // strictly greater
      expect(WitFrameDecoder.batteryPercent(3.60), 10);
      expect(WitFrameDecoder.batteryPercent(3.30), 0);
    });

    test('invalid chip date gives null sensor time', () {
      final f = Uint8List.fromList(imuFrame())..[3] = 0; // month 0
      expect(WitFrameDecoder.chipTimeMs(f), isNull);
    });
  });

  group('SensorSample.worldZ', () {
    test('sensor rotated 90° about X sees gravity on its Y axis', () {
      const h = 0.7071067811865476; // cos/sin of 45°
      const s = SensorSample(
        hostTimeUs: 0, sensorTimeMs: 0,
        ax: 0, ay: 1, az: 0, gx: 0, gy: 0, gz: 0,
        q0: h, q1: h, q2: 0, q3: 0,
      );
      expect(s.worldZ, closeTo(1.0, 1e-9));
    });
  });

  group('RateMonitor', () {
    SensorSample at(int ms) => SensorSample(
          hostTimeUs: ms * 1000, sensorTimeMs: ms,
          ax: 0, ay: 0, az: 1, gx: 0, gy: 0, gz: 0,
          q0: 1, q1: 0, q2: 0, q3: 0,
        );

    test('measures 200 Hz and counts dropped samples', () {
      final m = RateMonitor();
      for (var ms = 0; ms <= 1000; ms += 5) {
        if (ms == 500 || ms == 505) continue; // two lost samples
        m.add(at(ms));
      }
      expect(m.estimatedMissing, 2);
      expect(m.hz, closeTo(199, 1.5));
    });

    test('treats backwards or >2 s steps as clock jumps', () {
      final m = RateMonitor()
        ..add(at(1000))
        ..add(at(990))
        ..add(at(5000));
      expect(m.clockJumps, 2);
      expect(m.estimatedMissing, 0);
    });

    test('measures the rate again after a clock jump', () {
      final m = RateMonitor()..add(at(8323059)); // stale frame before 0x96 = 2
      for (var ms = 150000; ms <= 151000; ms += 5) {
        m.add(at(ms));
      }
      expect(m.clockJumps, 1);
      expect(m.hz, closeTo(200, 1));
    });
  });
}
