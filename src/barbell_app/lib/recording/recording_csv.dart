/// Reading raw recordings back from CSV, for import and reprocessing.
///
/// Two formats are accepted:
/// - ours ([Recording.toCsv]): `#` comment lines, then [Recording.csvHeader]
///   and 12 columns per row;
/// - Stance's IMU export (`ImuCsvWriter`): [stanceImuCsvHeader] and 11
///   columns per row, timestamped by the sensor clock only.
///
/// Validation and error texts follow Stance's `ImuCsvReader`: the header
/// must match exactly (a leading BOM is ignored), every row needs the right
/// column count, every number must parse, and at least 2 rows are needed.
library;

import '../sensor/sensor_sample.dart';
import 'recording.dart';

/// Stance's `ImuCsvWriter.HEADER_LINE`.
const referenceImuCsvHeader = 'Timestamp,Gyroscope X (deg/s),Gyroscope Y (deg/s),'
    'Gyroscope Z (deg/s),Accelerometer X (g),Accelerometer Y (g),'
    'Accelerometer Z (g),Quaternion W,Quaternion X,Quaternion Y,Quaternion Z';

/// A CSV that can't be read; [message] is shown to the user as is.
class RecordingCsvException implements Exception {
  RecordingCsvException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Samples read from a recording CSV.
class ParsedRecording {
  const ParsedRecording({
    required this.samples,
    required this.startedAt,
    this.sensorName,
  });

  final List<SensorSample> samples;

  /// From our `started=` comment, else the first sample's time.
  final DateTime startedAt;

  /// From our `sensor=` comment; null for Stance's export.
  final String? sensorName;

  /// The last sample's time.
  DateTime get endedAt => DateTime.fromMicrosecondsSinceEpoch(samples.last.hostTimeUs);

  /// As a [Recording], e.g. to save a copy with [RecordingStore.save].
  Recording toRecording() =>
      Recording(sensorName: sensorName ?? 'imported', startedAt: startedAt)
        ..samples.addAll(samples);
}

/// Parses [text] in either format. Throws [RecordingCsvException].
ParsedRecording parseRecordingCsv(String text) {
  final lines = text.split(RegExp(r'\r?\n'));
  String? sensorName;
  DateTime? started;
  var i = 0;
  // Our leading comment lines (and blank lines) before the header.
  for (; i < lines.length; i++) {
    final line = _stripBom(lines[i].trim());
    if (line.isEmpty) continue;
    if (!line.startsWith('#')) break;
    // `# sensor=<name> started=<ISO time>`; the name may contain spaces.
    final s = RegExp(r'started=(\S+)').firstMatch(line);
    if (s != null) started = DateTime.tryParse(s.group(1)!)?.toLocal();
    final n = RegExp(r'sensor=(.*?)(?:\s+started=|$)').firstMatch(line);
    if (n != null) sensorName = n.group(1)!.trim();
  }
  if (i >= lines.length) throw RecordingCsvException('CSV is empty');

  final header = _stripBom(lines[i].trim());
  final ours = header == Recording.csvHeader;
  if (!ours && header != referenceImuCsvHeader) {
    throw RecordingCsvException(
        'Unexpected CSV header. Expected exact export header line.');
  }
  final columns = ours ? 12 : 11;
  final samples = <SensorSample>[];
  for (i++; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final lineNo = i + 1;
    final parts = [for (final p in line.split(',')) p.trim()];
    if (parts.length != columns) {
      throw RecordingCsvException(
          'Line $lineNo: expected $columns columns, got ${parts.length}');
    }
    samples.add(ours ? _ourRow(parts, lineNo) : _referenceRow(parts, lineNo));
  }
  if (samples.length < 2) {
    throw RecordingCsvException(
        'Need at least 2 data rows, got ${samples.length}');
  }
  return ParsedRecording(
    samples: samples,
    startedAt: started ??
        DateTime.fromMicrosecondsSinceEpoch(samples.first.hostTimeUs),
    sensorName: sensorName,
  );
}

SensorSample _ourRow(List<String> p, int line) => SensorSample(
      hostTimeUs: _int(p[0], 'host_time_us', line),
      sensorTimeMs: p[1].isEmpty ? null : _int(p[1], 'sensor_time_ms', line),
      ax: _double(p[2], 'ax_g', line),
      ay: _double(p[3], 'ay_g', line),
      az: _double(p[4], 'az_g', line),
      gx: _double(p[5], 'gx_dps', line),
      gy: _double(p[6], 'gy_dps', line),
      gz: _double(p[7], 'gz_dps', line),
      q0: _double(p[8], 'q0', line),
      q1: _double(p[9], 'q1', line),
      q2: _double(p[10], 'q2', line),
      q3: _double(p[11], 'q3', line),
    );

/// Stance's column order: timestamp, gyro, accel, quaternion. Its only
/// clock is the sensor's, so it also stands in for the phone clock.
SensorSample _referenceRow(List<String> p, int line) {
  final ms = _chipTimeMs(p[0]);
  if (ms == null) {
    throw RecordingCsvException('Line $line: invalid Timestamp value "${p[0]}"');
  }
  return SensorSample(
    hostTimeUs: ms * 1000,
    sensorTimeMs: ms,
    gx: _double(p[1], 'Gyro X', line),
    gy: _double(p[2], 'Gyro Y', line),
    gz: _double(p[3], 'Gyro Z', line),
    ax: _double(p[4], 'Acc X', line),
    ay: _double(p[5], 'Acc Y', line),
    az: _double(p[6], 'Acc Z', line),
    q0: _double(p[7], 'Q W', line),
    q1: _double(p[8], 'Q X', line),
    q2: _double(p[9], 'Q Y', line),
    q3: _double(p[10], 'Q Z', line),
  );
}

/// `yyyy-MM-dd HH:mm:ss.SSS` or with a `T`, read as UTC (Stance's
/// `chipTimeFormatters`).
final _chipTime =
    RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})\.(\d{3})$');

int? _chipTimeMs(String raw) {
  final m = _chipTime.firstMatch(raw);
  if (m == null) return null;
  final f = [for (var g = 1; g <= 7; g++) int.parse(m.group(g)!)];
  return DateTime.utc(f[0], f[1], f[2], f[3], f[4], f[5], f[6])
      .millisecondsSinceEpoch;
}

double _double(String raw, String field, int line) =>
    double.tryParse(raw) ??
    (throw RecordingCsvException('Line $line: invalid $field value "$raw"'));

int _int(String raw, String field, int line) =>
    int.tryParse(raw) ??
    (throw RecordingCsvException('Line $line: invalid $field value "$raw"'));

String _stripBom(String s) =>
    s.startsWith('﻿') ? s.substring(1).trim() : s;
