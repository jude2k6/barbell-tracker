import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../sensor/sensor_sample.dart';

/// Raw samples from one set, saved as CSV so the Python reference pipeline
/// (and later the Dart port) can be run against real recordings.
class Recording {
  Recording({required this.sensorName, required this.startedAt});

  final String sensorName;
  final DateTime startedAt;
  final samples = <SensorSample>[];

  static const csvHeader =
      'host_time_us,sensor_time_ms,ax_g,ay_g,az_g,gx_dps,gy_dps,gz_dps,q0,q1,q2,q3';

  String toCsv() {
    final b = StringBuffer()
      ..writeln('# sensor=$sensorName started=${startedAt.toUtc().toIso8601String()}')
      ..writeln(csvHeader);
    for (final s in samples) {
      b.writeln([
        s.hostTimeUs, s.sensorTimeMs ?? '',
        s.ax, s.ay, s.az, s.gx, s.gy, s.gz,
        s.q0, s.q1, s.q2, s.q3,
      ].join(','));
    }
    return b.toString();
  }
}

/// CSV recordings under `<base>/recordings/`. The base defaults to the app
/// documents directory and can be injected for tests.
class RecordingStore {
  RecordingStore({Future<Directory> Function()? baseDirectory})
      : _base = baseDirectory ?? getApplicationDocumentsDirectory;

  static const _subdir = 'recordings';

  final Future<Directory> Function() _base;

  Future<Directory> _dir() async {
    final base = await _base();
    final dir = Directory('${base.path}/$_subdir');
    return dir.create(recursive: true);
  }

  Future<File> save(Recording r) async {
    final dir = await _dir();
    final stamp = r.startedAt.toUtc().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/$stamp.csv');
    return file.writeAsString(r.toCsv());
  }

  /// Path of [file] relative to the base directory, e.g.
  /// `recordings/2026-…Z.csv`. Stored in sessions instead of absolute paths,
  /// which change on iOS when the app container moves.
  String relativePath(File file) =>
      '$_subdir/${file.uri.pathSegments.last}';

  /// Resolves a path produced by [relativePath].
  Future<File> resolve(String relative) async =>
      File('${(await _base()).path}/$relative');

  Future<List<File>> list() async {
    final dir = await _dir();
    final files = dir.listSync().whereType<File>()
        .where((f) => f.path.endsWith('.csv')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }
}
