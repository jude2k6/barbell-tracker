import 'dart:convert';
import 'dart:io';

import 'package:barbell_app/workout/file_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('log line format matches Stance', () {
    final t = DateTime(2026, 10, 7, 9, 5, 3, 42);
    expect(formatLogLine(t, 'I', 'AppLoad', 'hello'),
        '2026-10-07 09:05:03.042 I/AppLoad: hello');
    final withStack = formatLogLine(t, 'E', 'X', 'boom', StackTrace.fromString('a\nb\n'));
    expect(withStack, '2026-10-07 09:05:03.042 E/X: boom\na\nb');
  });

  group('trimLogToLimit', () {
    test('leaves text that fits alone', () {
      expect(trimLogToLimit('a\nb\n', maxBytes: 100), 'a\nb\n');
    });

    test('drops the oldest 10 lines at a time until it fits', () {
      final lines = [for (var i = 0; i < 100; i++) 'line${i.toString().padLeft(3, '0')}'];
      final text = '${lines.join('\n')}\n'; // 8 bytes a line
      // 100 lines = 800 bytes; limit 500 needs 38 lines dropped, done as 40.
      final trimmed = trimLogToLimit(text, maxBytes: 500, dropLines: 10);
      expect(trimmed, '${lines.sublist(40).join('\n')}\n');
      // Limit 100 (12 lines): 100 -> 90 -> ... -> 10 lines left.
      final small = trimLogToLimit(text, maxBytes: 100, dropLines: 10);
      expect(small, '${lines.sublist(90).join('\n')}\n');
    });

    test('counts bytes, not characters', () {
      final text = '${List.filled(30, 'é').join('\n')}\n'; // 3 bytes a line
      final trimmed = trimLogToLimit(text, maxBytes: 60, dropLines: 10);
      expect(utf8.encode(trimmed).length, lessThanOrEqualTo(60));
      expect(trimmed.split('\n').length - 1, 20);
    });

    test('empties the file if nothing can fit', () {
      expect(trimLogToLimit('abcdef\n', maxBytes: 2), '');
    });
  });

  group('FileLogger', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('filelog'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('appends in order and creates the folder', () async {
      final log = FileLogger(File('${dir.path}/debug_logs/$fileLogName'));
      await log.open();
      expect(log.sharablePath, isNotNull);
      log.append('one');
      log.append('two');
      await log.flush();
      expect(log.file.readAsStringSync(), 'one\ntwo\n');
    });

    test('trims every 10th line once over the cap', () async {
      final log = FileLogger(File('${dir.path}/l.log'), maxBytes: 200);
      await log.open();
      for (var i = 0; i < 100; i++) {
        log.append('line ${i.toString().padLeft(3, '0')}'); // 9 bytes
      }
      await log.flush();
      final text = log.file.readAsStringSync();
      // Checked after every 10 lines, so never more than 10 lines over.
      expect(utf8.encode(text).length, lessThanOrEqualTo(200 + 10 * 9));
      expect(text.trimRight().split('\n').last, 'line 099');
      expect(text, isNot(contains('line 000')));
    });

    test('sharablePath is null before the file exists', () {
      expect(FileLogger(File('${dir.path}/none.log')).sharablePath, isNull);
    });
  });

  test('AppLog writes to the file and survives being uninitialised', () async {
    AppLog.i('T', 'before init'); // no-op on file
    final dir = Directory.systemTemp.createTempSync('applog');
    addTearDown(() => dir.deleteSync(recursive: true));
    await AppLog.init(directory: dir);
    AppLog.w('Tag', 'careful', StateError('x'));
    await AppLog.file!.flush();
    final text = File('${dir.path}/debug_logs/$fileLogName').readAsStringSync();
    expect(text, contains('========== APP LOADED BEGIN =========='));
    expect(text, contains(RegExp(r'W/Tag: careful: Bad state: x')));
  });
}
