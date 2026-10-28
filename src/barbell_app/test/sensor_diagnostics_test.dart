import 'dart:io';

import 'package:barbell_app/recording/recording.dart';
import 'package:barbell_app/sensor/orientation.dart';
import 'package:barbell_app/sensor/sensor_sample.dart';
import 'package:barbell_app/sensor/witmotion/witmotion_stats.dart';
import 'package:barbell_app/ui/app_scope.dart';
import 'package:barbell_app/ui/debug_menu_page.dart';
import 'package:barbell_app/ui/sensor_diagnostics_page.dart';
import 'package:barbell_app/workout/preferences.dart';
import 'package:barbell_app/workout/sensor_controller.dart';
import 'package:barbell_app/workout/sensor_diagnostics.dart';
import 'package:barbell_app/workout/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sensor_link.dart';

/// A sample 5 ms after the previous one with this accel/gyro and reference
/// orientation (roll/pitch in degrees).
SensorSample sample(
  int i, {
  (double, double, double) accel = (0, 0, 1),
  (double, double, double) gyro = (0, 0, 0),
  double refRoll = 0,
  int? sensorTimeMs,
}) {
  final (w, x, y, z) = eulerToQuaternion(refRoll, 0, 0);
  return SensorSample(
    hostTimeUs: i * 5000,
    sensorTimeMs: sensorTimeMs,
    ax: accel.$1, ay: accel.$2, az: accel.$3,
    gx: gyro.$1, gy: gyro.$2, gz: gyro.$3,
    q0: w, q1: x, q2: y, q3: z,
  );
}

void main() {
  group('tiltDifferenceDeg', () {
    test('ignores yaw and measures tilt', () {
      final flat = eulerToQuaternion(0, 0, 0);
      expect(tiltDifferenceDeg(flat, eulerToQuaternion(0, 0, 70)),
          closeTo(0, 1e-6));
      expect(tiltDifferenceDeg(flat, eulerToQuaternion(12, 0, 30)),
          closeTo(12, 1e-6));
    });
  });

  group('TiltComparison', () {
    test('agreeing filters read ~0°, a tilted reference reads its tilt', () {
      final c = TiltComparison();
      for (var i = 0; i < 200; i++) {
        c.add(sample(i, gyro: (0.5, -0.2, 0.1)));
      }
      // Mahony's steady-state lag from a gyro bias is bias / kp.
      expect(c.tiltDiffDeg, closeTo(0.5 / 2, 0.05));
      expect(c.biasX, closeTo(0.5, 1e-6));
      expect(c.biasY, closeTo(-0.2, 1e-6));

      c.add(sample(200, refRoll: 10));
      expect(c.tiltDiffDeg, closeTo(10, 0.3)); // plus the bias lag
    });

    test('logs one movement with its velocity, no error when both agree', () {
      final c = TiltComparison();
      final ended = <MovementResult>[];
      c.onMovement = ended.add;
      var i = 0;
      for (; i < 200; i++) {
        c.add(sample(i)); // 1 s still
      }
      for (var k = 0; k < 120; k++, i++) {
        c.add(sample(i, accel: (0, 0, 1.5))); // 0.6 s at +0.5 g
      }
      expect(c.movingS, isNotNull);
      for (var k = 0; k < 200; k++, i++) {
        c.add(sample(i)); // settle
      }
      expect(c.movingS, isNull);
      expect(ended, hasLength(1));
      final m = c.movements.single;
      expect(m.durationS, closeTo(0.6, 0.01));
      expect(m.peakVelocity, closeTo(0.5 * 9.81 * 0.6, 0.05));
      expect(m.peakVelocityError, closeTo(0, 1e-3));
      expect(m.peakTiltDiffDeg, closeTo(0, 0.05));
    });

    test('drops blips shorter than the minimum', () {
      final c = TiltComparison();
      var i = 0;
      for (; i < 50; i++) {
        c.add(sample(i));
      }
      for (var k = 0; k < 10; k++, i++) {
        c.add(sample(i, accel: (0, 0, 1.5)));
      }
      for (var k = 0; k < 200; k++, i++) {
        c.add(sample(i));
      }
      expect(c.movements, isEmpty);
    });

    test('without a reference the errors are blank', () {
      final c = TiltComparison()..hasReference = false;
      var i = 0;
      for (; i < 50; i++) {
        c.add(sample(i, refRoll: 20));
      }
      expect(c.tiltDiffDeg, 0);
      for (var k = 0; k < 100; k++, i++) {
        c.add(sample(i, accel: (0, 0, 1.5)));
      }
      for (var k = 0; k < 200; k++, i++) {
        c.add(sample(i));
      }
      final m = c.movements.single;
      expect(m.peakTiltDiffDeg, isNull);
      expect(m.peakVelocityError, isNull);
      expect(m.peakVelocity, greaterThan(0));
    });

    test('counts sensor counter steps, gaps in their own bucket', () {
      final c = TiltComparison();
      final times = [1000, 1040, 1080, 1120, 1400, 1440];
      for (final (i, t) in times.indexed) {
        c.add(sample(i, sensorTimeMs: t));
      }
      expect(c.counterSteps, {40: 4, TiltComparison.gapStep: 1});
    });
  });

  group('WitLinkStats', () {
    test('histograms and gaps', () {
      final s = WitLinkStats();
      s.addNotification(bytes: 20, frames: 1, arrivalUs: 0);
      s.addNotification(bytes: 80, frames: 4, arrivalUs: 40000);
      s.addNotification(bytes: 20, frames: 1, arrivalUs: 100000);
      expect(s.notificationLengths, {20: 2, 80: 1});
      expect(s.framesPerNotification, {1: 2, 4: 1});
      expect(s.frames, 6);
      final g = s.gapsMs!;
      expect(g.mean, closeTo(50, 1e-9));
      expect(g.max, closeTo(60, 1e-9));
    });
  });

  test('Preferences keep clock mode and tilt gains', () {
    const p = Preferences(
        clockMode: true, tiltGains: TiltGains(kp: 1.5, ki: 0, accelGate: 0.2));
    final back = Preferences.fromJson(p.toJson());
    expect(back.clockMode, isTrue);
    expect(back.tiltGains, p.tiltGains);
    expect(const Preferences().toJson().containsKey('tiltGains'), isFalse);
  });

  group('Sensor diagnostics screen', () {
    late Directory dir;
    late SensorController sensor;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('diagnostics');
      sensor = SensorController(reconnectDelays: const []);
    });

    tearDown(() {
      sensor.dispose();
      dir.deleteSync(recursive: true);
    });

    testWidgets('opens from the Debug Menu and shows incoming samples',
        (tester) async {
      final link = FakeSensorLink();
      await sensor.connect(link);
      await tester.pumpWidget(AppScope(
        sensor: sensor,
        sessions: SessionStore(baseDirectory: () async => dir),
        recordings: RecordingStore(baseDirectory: () async => dir),
        child: const MaterialApp(home: DebugMenuPage()),
      ));
      await tester.tap(find.byKey(const Key('sensorDiagnosticsMenu')));
      await tester.pumpAndSettle();
      expect(find.text('Sensor diagnostics'), findsOneWidget);
      expect(find.text('Stream mode'), findsOneWidget);

      for (var i = 0; i < 20; i++) {
        link.emit(i);
      }
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Tilt difference now'), findsOneWidget);
      expect(find.text('20'), findsOneWidget); // samples in the last second

      await tester.tap(find.byTooltip('Go back').last);
      await tester.pumpAndSettle();
    });

    testWidgets('fits a phone screen with movements listed', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final link = FakeSensorLink();
      await sensor.connect(link);
      await tester.pumpWidget(AppScope(
        sensor: sensor,
        sessions: SessionStore(baseDirectory: () async => dir),
        recordings: RecordingStore(baseDirectory: () async => dir),
        child: const MaterialApp(home: SensorDiagnosticsPage()),
      ));
      var i = 0;
      for (var rep = 0; rep < 3; rep++) {
        for (var k = 0; k < 200; k++) {
          link.emit(i++);
        }
        for (var k = 0; k < 120; k++) {
          link.emit(i++, az: 1.5);
        }
      }
      for (var k = 0; k < 200; k++) {
        link.emit(i++);
      }
      await tester.pump(const Duration(seconds: 1));
      await tester.scrollUntilVisible(find.text('d err cm'), 200);
      expect(find.text('d err cm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows and saves the mode while no sensor is connected',
        (tester) async {
      final prefs = PreferencesStore(baseDirectory: () async => dir);
      await tester.pumpWidget(AppScope(
        sensor: sensor,
        sessions: SessionStore(baseDirectory: () async => dir),
        recordings: RecordingStore(baseDirectory: () async => dir),
        preferences: prefs,
        child: const MaterialApp(home: SensorDiagnosticsPage()),
      ));
      await tester.tap(find.byKey(const Key('modeClock')));
      await tester.pump();
      expect(prefs.value.clockMode, isTrue);
      expect(find.textContaining('Clock: the sensor sends'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
