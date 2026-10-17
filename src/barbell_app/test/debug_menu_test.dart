import 'dart:io';

import 'package:barbell_app/recording/recording.dart';
import 'package:barbell_app/ui/app_scope.dart';
import 'package:barbell_app/ui/debug_menu_page.dart';
import 'package:barbell_app/ui/home_page.dart';
import 'package:barbell_app/workout/file_log.dart';
import 'package:barbell_app/workout/preferences.dart';
import 'package:barbell_app/workout/saved_sensor.dart';
import 'package:barbell_app/workout/sensor_controller.dart';
import 'package:barbell_app/workout/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sensor_link.dart';

void main() {
  late Directory dir;
  late SensorController sensor;
  late PreferencesStore prefs;
  late SavedSensor saved;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('debug_menu');
    sensor = SensorController(reconnectDelays: const []);
    prefs = PreferencesStore(baseDirectory: () async => dir);
    saved = SavedSensor(
      sensor: sensor,
      preferences: prefs,
      find: (id, timeout) async => null,
    );
  });

  tearDown(() async {
    AppLog.reset();
    sensor.dispose();
    dir.deleteSync(recursive: true);
  });

  Widget app(Widget home) => AppScope(
        sensor: sensor,
        sessions: SessionStore(baseDirectory: () async => dir),
        recordings: RecordingStore(baseDirectory: () async => dir),
        preferences: prefs,
        savedSensor: saved,
        child: MaterialApp(home: home),
      );

  testWidgets('Home menu opens the Debug Menu',
      (tester) async {
    await tester.runAsync(() => AppLog.init(directory: dir));
    await tester.pumpWidget(app(const HomePage()));
    await tester.tap(find.byKey(const Key('homeMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Debug Menu'));
    await tester.pumpAndSettle();
    expect(find.text('File logging'), findsOneWidget);
    expect(find.text('Logs are saved automatically (last 5 MB). Share to send for support.'),
        findsOneWidget);
    expect(find.text('Share debug log'), findsOneWidget);
    expect(find.text('Forget saved BLE devices'), findsOneWidget);
  });

  testWidgets('Share debug log hands the log file to the share sheet',
      (tester) async {
    await tester.runAsync(() => AppLog.init(directory: dir));
    final shared = <String>[];
    await tester.pumpWidget(app(DebugMenuPage(share: (p) async => shared.add(p))));
    await tester.runAsync(() async {
      await tester.tap(find.text('Share debug log'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(shared, ['${dir.path}/debug_logs/$fileLogName']);
  });

  testWidgets('Forget saved BLE devices clears the saved sensor', (tester) async {
    await tester.runAsync(() async {
      await prefs.load();
      await sensor.connect(FakeSensorLink(id: 'AA:01'));
    });
    expect(saved.hasSaved, isTrue);
    await tester.pumpWidget(app(const DebugMenuPage()));
    await tester.runAsync(() async {
      await tester.tap(find.text('Forget saved BLE devices'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(saved.hasSaved, isFalse);
  });

  testWidgets('Device stream page: Start collects, Stop keeps the data',
      (tester) async {
    final link = FakeSensorLink();
    await tester.runAsync(() => sensor.connect(link));
    await tester.pumpWidget(app(const DebugMenuPage()));
    await tester.tap(find.text('Test device data stream'));
    await tester.pumpAndSettle();
    expect(find.text('Test device stream'), findsOneWidget);
    expect(find.text('Is Stationary'), findsOneWidget);
    await tester.tap(find.byKey(const Key('streamStart')));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      link.emit(i);
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('streamStop')));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('streamStop'))).onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
