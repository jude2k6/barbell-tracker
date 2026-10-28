import 'dart:io';

import 'package:barbell_app/recording/recording.dart';
import 'package:barbell_app/ui/app_scope.dart';
import 'package:barbell_app/ui/calibration_page.dart';
import 'package:barbell_app/ui/debug_menu_page.dart';
import 'package:barbell_app/ui/device_page.dart';
import 'package:barbell_app/workout/sensor_controller.dart';
import 'package:barbell_app/workout/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sensor_link.dart';

void main() {
  late Directory dir;
  late SensorController sensor;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('calibration');
    sensor = SensorController(reconnectDelays: const []);
  });

  tearDown(() {
    sensor.dispose();
    dir.deleteSync(recursive: true);
  });

  Widget app(Widget home) => AppScope(
        sensor: sensor,
        sessions: SessionStore(baseDirectory: () async => dir),
        recordings: RecordingStore(baseDirectory: () async => dir),
        child: MaterialApp(home: home),
      );

  VoidCallback? startButton(WidgetTester tester) => tester
      .widget<FilledButton>(find.descendant(
          of: find.byKey(const Key('calibrationStart')),
          matching: find.byType(FilledButton)))
      .onPressed;

  const instructions =
      'Place the WitMotion IMU on a flat, level surface and keep it still. '
      'Calibration runs for 10 seconds after you start.';
  const readyHint = 'When you are ready, tap Start calibration.';

  testWidgets('Debug Menu opens Calibration; without a sensor Start is off',
      (tester) async {
    await tester.pumpWidget(app(const DebugMenuPage()));
    await tester.tap(find.byKey(const Key('calibrationMenu')));
    await tester.pumpAndSettle();
    expect(find.byType(CalibrationPage), findsOneWidget);
    expect(find.text('Calibration'), findsOneWidget);
    expect(find.text(instructions), findsOneWidget);
    expect(
        find.text(
            'Connect a WitMotion IMU from the Devices screen to calibrate.'),
        findsOneWidget);
    expect(find.text('Start calibration'), findsOneWidget);
    expect(startButton(tester), isNull);
    await tester.tap(find.byKey(const Key('calibrationBack')));
    await tester.pumpAndSettle();
    expect(find.byType(CalibrationPage), findsNothing);
  });

  testWidgets('Start sends the command at once, counts 10 s, then completes',
      (tester) async {
    final link = FakeSensorLink();
    await tester.runAsync(() => sensor.connect(link));
    await tester.pumpWidget(app(const CalibrationPage()));
    expect(find.text(readyHint), findsOneWidget);

    await tester.tap(find.text('Start calibration'));
    await tester.pump();
    expect(link.calibrations, 1);
    expect(find.text('10 s'), findsOneWidget);
    expect(find.text('Calibrating…'), findsOneWidget);
    expect(startButton(tester), isNull);

    await tester.pump(const Duration(seconds: 9));
    expect(find.text('1 s'), findsOneWidget);
    expect(find.text('Calibration complete'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Calibration complete'), findsOneWidget);
    expect(find.text('IMU calibration finished successfully.'), findsOneWidget);
    expect(link.calibrations, 1);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CalibrationPage), findsOneWidget);
    expect(find.text(readyHint), findsOneWidget);
    expect(startButton(tester), isNotNull);
  });

  testWidgets('A failed write stops the run and says so', (tester) async {
    final link = FakeSensorLink()..calibrateError = StateError('write failed');
    await tester.runAsync(() => sensor.connect(link));
    await tester.pumpWidget(app(const CalibrationPage()));
    await tester.tap(find.text('Start calibration'));
    await tester.pumpAndSettle();
    expect(find.text('Calibration failed'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text(readyHint), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('Calibration complete'), findsNothing);
  });

  testWidgets('Leaving mid-run cancels the countdown', (tester) async {
    final link = FakeSensorLink();
    await tester.runAsync(() => sensor.connect(link));
    await tester.pumpWidget(app(const DebugMenuPage()));
    await tester.tap(find.byKey(const Key('calibrationMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start calibration'));
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byKey(const Key('calibrationBack')));
    await tester.pumpAndSettle();
    expect(find.byType(CalibrationPage), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Calibration complete'), findsNothing);
    expect(link.calibrations, 1);
  });

  testWidgets('Device page Calibrate opens the Calibration page',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => sensor.connect(FakeSensorLink()));
    await tester.pumpWidget(app(const DevicePage()));
    await tester.pump();
    await tester.tap(find.text('Calibrate (lay flat)'));
    await tester.pumpAndSettle();
    expect(find.byType(CalibrationPage), findsOneWidget);
    expect(find.text(readyHint), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
