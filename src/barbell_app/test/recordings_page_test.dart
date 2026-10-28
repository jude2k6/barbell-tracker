import 'dart:io';

import 'package:barbell_app/recording/recording.dart';
import 'package:barbell_app/ui/app_scope.dart';
import 'package:barbell_app/ui/recordings_page.dart';
import 'package:barbell_app/workout/sensor_controller.dart';
import 'package:barbell_app/workout/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late RecordingStore recordings;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('recordings_page');
    recordings = RecordingStore(baseDirectory: () async => dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<List<List<String>>> open(WidgetTester tester) async {
    final shared = <List<String>>[];
    await tester.pumpWidget(AppScope(
      sensor: SensorController(),
      sessions: SessionStore(baseDirectory: () async => dir),
      recordings: recordings,
      child: MaterialApp(
        home: RecordingsPage(
          share: (files) async =>
              shared.add([for (final f in files) f.uri.pathSegments.last]),
        ),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    return shared;
  }

  testWidgets('shares one recording or all of them', (tester) async {
    await tester.runAsync(() async {
      for (final minute in [0, 5]) {
        await recordings.save(Recording(
            sensorName: 'WT', startedAt: DateTime.utc(2026, 10, 28, 9, minute)));
      }
    });
    final shared = await open(tester);
    expect(find.text('2026-10-28T09-05-00.000Z.csv'), findsOneWidget);

    await tester.tap(
        find.byKey(const ValueKey('shareRecording-2026-10-28T09-00-00.000Z.csv')));
    await tester.tap(find.byKey(const Key('shareAllRecordings')));
    expect(shared, [
      ['2026-10-28T09-00-00.000Z.csv'],
      ['2026-10-28T09-05-00.000Z.csv', '2026-10-28T09-00-00.000Z.csv'],
    ]);
  });

  testWidgets('Share all is disabled with no recordings', (tester) async {
    final shared = await open(tester);
    expect(find.text('No recordings yet.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shareAllRecordings')));
    expect(shared, isEmpty);
  });
}
