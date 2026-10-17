import 'dart:io';

import 'package:barbell_app/sensor/sensor_link.dart';
import 'package:barbell_app/workout/preferences.dart';
import 'package:barbell_app/workout/saved_sensor.dart';
import 'package:barbell_app/workout/sensor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sensor_link.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late Directory dir;
  late SensorController sensor;
  late PreferencesStore prefs;
  late List<(String, Duration)> finds;
  FakeSensorLink? nearby;

  SavedSensor make({Future<void>? loaded}) => SavedSensor(
        sensor: sensor,
        preferences: prefs,
        preferencesLoaded: loaded,
        find: (id, timeout) async {
          finds.add((id, timeout));
          return nearby;
        },
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('saved_sensor');
    sensor = SensorController(reconnectDelays: const []);
    prefs = PreferencesStore(baseDirectory: () async => dir);
    finds = [];
    nearby = FakeSensorLink(id: 'AA:01');
  });

  tearDown(() {
    sensor.dispose();
    dir.deleteSync(recursive: true);
  });

  test('saves the sensor once it is streaming, and keeps it on disconnect', () async {
    final saved = make();
    expect(saved.hasSaved, isFalse);
    await sensor.connect(FakeSensorLink(id: 'AA:01'));
    expect(saved.savedId, 'AA:01');
    await sensor.disconnect();
    expect(saved.savedId, 'AA:01');

    final reloaded = PreferencesStore(baseDirectory: () async => dir);
    await reloaded.load();
    expect(reloaded.value.savedSensorId, 'AA:01');
  });

  test('a failed connect saves nothing', () async {
    final saved = make();
    await sensor.connect(FakeSensorLink(failConnects: 1));
    expect(saved.hasSaved, isFalse);
  });

  test('autoConnect scans for the saved id with a 12 s timeout and connects', () async {
    await prefs.update(const Preferences(savedSensorId: 'AA:01'));
    final saved = make();
    expect(await saved.autoConnect(permitted: true), isTrue);
    expect(finds, [('AA:01', const Duration(seconds: 12))]);
    expect(sensor.link, same(nearby));
    expect(sensor.isStreaming, isTrue);
  });

  test('autoConnect does nothing without a saved sensor', () async {
    final saved = make();
    expect(await saved.autoConnect(permitted: true), isFalse);
    expect(finds, isEmpty);
  });

  test('autoConnect waits for the preferences to load', () async {
    final loaded = prefs.update(const Preferences(savedSensorId: 'AA:01'));
    final saved = make(loaded: Future<void>.delayed(const Duration(milliseconds: 5), () => loaded));
    expect(await saved.autoConnect(permitted: true), isTrue);
  });

  test('without Bluetooth access it does not scan and keeps the attempt', () async {
    await prefs.update(const Preferences(savedSensorId: 'AA:01'));
    final saved = make();
    expect(await saved.autoConnect(permitted: false), isFalse);
    expect(finds, isEmpty);
    expect(await saved.autoConnect(permitted: true), isTrue);
  });

  test('tries once per app run, even if the sensor was not found', () async {
    await prefs.update(const Preferences(savedSensorId: 'AA:01'));
    nearby = null;
    final saved = make();
    expect(await saved.autoConnect(permitted: true), isFalse);
    expect(sensor.state, LinkState.disconnected);
    nearby = FakeSensorLink(id: 'AA:01');
    expect(await saved.autoConnect(permitted: true), isFalse);
    expect(finds, hasLength(1));
  });

  test('does not run when a sensor is already connected', () async {
    await prefs.update(const Preferences(savedSensorId: 'AA:01'));
    await sensor.connect(FakeSensorLink(id: 'AA:01'));
    final saved = make();
    expect(await saved.autoConnect(permitted: true), isFalse);
    expect(finds, isEmpty);
  });

  test('a failed auto-connect is not retried', () async {
    await prefs.update(const Preferences(savedSensorId: 'AA:01'));
    nearby = FakeSensorLink(id: 'AA:01', failConnects: 1);
    final saved = make();
    expect(await saved.autoConnect(permitted: true), isFalse);
    await settle();
    expect(nearby!.connectCalls, 1);
    expect(sensor.state, LinkState.failed);
  });

  test('forget disconnects and clears the saved sensor', () async {
    final saved = make();
    final link = FakeSensorLink(id: 'AA:01');
    await sensor.connect(link);
    expect(saved.hasSaved, isTrue);
    await saved.forget();
    expect(link.disconnectCalls, 1);
    expect(sensor.link, isNull);
    expect(saved.hasSaved, isFalse);

    final reloaded = PreferencesStore(baseDirectory: () async => dir);
    await reloaded.load();
    expect(reloaded.value.savedSensorId, isNull);
  });
}
