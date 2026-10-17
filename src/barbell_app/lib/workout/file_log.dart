import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Stance's limits for the debug log file (`AppFileLogLimitsKt`).
const fileLogName = 'stance-app.log';
const fileLogMaxBytes = 5242880;
const fileLogTrimCheckInterval = 10;
const fileLogTrimLines = 10;

/// One log line as Stance writes it (`DebugFileLogRepositoryImpl`):
/// `yyyy-MM-dd HH:mm:ss.SSS L/tag: message`, with the stack trace on the
/// following lines when there is one.
String formatLogLine(
  DateTime time,
  String level,
  String tag,
  String message, [
  StackTrace? stack,
]) {
  String two(int n) => n.toString().padLeft(2, '0');
  final ms = time.millisecond.toString().padLeft(3, '0');
  final stamp = '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-'
      '${two(time.day)} ${two(time.hour)}:${two(time.minute)}:'
      '${two(time.second)}.$ms';
  final line = '$stamp $level/$tag: $message';
  return stack == null ? line : '$line\n${stack.toString().trimRight()}';
}

/// Drops the oldest [dropLines] lines at a time until [text] fits in
/// [maxBytes] (Stance's `trimIfOverLimit`). Returns [text] unchanged if it
/// already fits.
String trimLogToLimit(
  String text, {
  int maxBytes = fileLogMaxBytes,
  int dropLines = fileLogTrimLines,
}) {
  if (utf8.encode(text).length <= maxBytes) return text;
  final lines = text.split('\n');
  // The text ends with a newline, which leaves an empty last element.
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  var start = 0;
  // Bytes of lines[start..], each counted with its newline.
  var bytes = utf8.encode(text).length;
  while (bytes > maxBytes && start < lines.length) {
    final end = start + dropLines < lines.length ? start + dropLines : lines.length;
    for (var i = start; i < end; i++) {
      bytes -= utf8.encode(lines[i]).length + 1;
    }
    start = end;
  }
  if (start >= lines.length) return '';
  return '${lines.sublist(start).join('\n')}\n';
}

/// Appends lines to one log file and keeps it under a size cap: every
/// [trimCheckInterval] lines it checks the size and, over [maxBytes], cuts
/// the oldest lines (Stance's `DebugFileLogFileStore`). Writes run one after
/// another so lines stay in order; failures are swallowed.
class FileLogger {
  FileLogger(
    this.file, {
    this.maxBytes = fileLogMaxBytes,
    this.trimCheckInterval = fileLogTrimCheckInterval,
    this.trimLines = fileLogTrimLines,
  });

  final File file;
  final int maxBytes;
  final int trimCheckInterval;
  final int trimLines;

  Future<void> _queue = Future.value();
  int _sinceTrimCheck = 0;

  /// Creates the file (and its folder) if needed.
  Future<void> open() => _enqueue(() async {
        await file.parent.create(recursive: true);
        if (!await file.exists()) await file.create();
      });

  void append(String line) {
    _enqueue(() async {
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      if (++_sinceTrimCheck >= trimCheckInterval) {
        _sinceTrimCheck = 0;
        await _trim();
      }
    });
  }

  /// Completes once everything appended so far is on disk.
  Future<void> flush() => _queue;

  /// The log file's path, or null if there is none yet.
  String? get sharablePath => file.existsSync() ? file.path : null;

  Future<void> _trim() async {
    if (await file.length() <= maxBytes) return;
    final text = await file.readAsString();
    await file.writeAsString(trimLogToLimit(text,
        maxBytes: maxBytes, dropLines: trimLines));
  }

  Future<void> _enqueue(Future<void> Function() task) =>
      _queue = _queue.then((_) => task()).catchError((Object _) {});
}

/// App-wide log, Stance's `StanceLog`: does nothing until [init], then
/// writes to the log file as well as the console.
class AppLog {
  AppLog._();

  static FileLogger? _file;

  /// The active file logger, for the debug menu's "Share debug log".
  static FileLogger? get file => _file;

  /// Turns file logging off again (tests).
  @visibleForTesting
  static void reset() => _file = null;

  /// Opens `debug_logs/stance-app.log` in the app documents folder, or
  /// [directory] if given, and writes the app-start lines.
  static Future<void> init({Directory? directory}) async {
    try {
      final base = directory ?? await getApplicationDocumentsDirectory();
      final logger = FileLogger(File('${base.path}/debug_logs/$fileLogName'));
      await logger.open();
      _file = logger;
      for (final line in appLoadedLines(DateTime.now())) {
        i('AppLoad', line);
      }
    } catch (e) {
      debugPrint('File logging unavailable: $e');
    }
  }

  /// The block logged at start-up (Stance's `AppLoadLogReporter`).
  static List<String> appLoadedLines(DateTime now) => [
        '========== APP LOADED BEGIN ==========',
        'event=app_loaded_from_memory',
        'isDebug=$kDebugMode',
        'platform=${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'loadedAtUtc=${now.toUtc().toIso8601String()}',
        'loadedAtLocal=${now.toIso8601String()}',
        'deviceTimezone=${now.timeZoneName} (UTC${now.timeZoneOffset.isNegative ? '-' : '+'}'
            '${now.timeZoneOffset.inHours.abs().toString().padLeft(2, '0')}:'
            '${(now.timeZoneOffset.inMinutes.abs() % 60).toString().padLeft(2, '0')})',
        '========== APP LOADED END ==========',
      ];

  static void d(String tag, String message) => _log('D', tag, message);
  static void i(String tag, String message) => _log('I', tag, message);
  static void w(String tag, String message, [Object? error, StackTrace? stack]) =>
      _log('W', tag, error == null ? message : '$message: $error', stack);
  static void e(String tag, String message, [Object? error, StackTrace? stack]) =>
      _log('E', tag, error == null ? message : '$message: $error', stack);

  static void _log(String level, String tag, String message, [StackTrace? stack]) {
    final file = _file;
    if (file == null) return;
    debugPrint('$level/$tag: $message');
    file.append(formatLogLine(DateTime.now(), level, tag, message, stack));
  }
}
