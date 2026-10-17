/// WitMotion BLE IMU protocol, as used by the reference app.
///
/// See notes/android-apk-decompiled.md §1 for where each value comes from.
library;

import 'dart:typed_data';

import '../sensor_sample.dart';

/// GATT identifiers. Note the non-standard `…805f9a34fb` base on the
/// WitMotion service and characteristics.
class WitUuids {
  static const service = '0000ffe5-0000-1000-8000-00805f9a34fb';
  static const notify = '0000ffe4-0000-1000-8000-00805f9a34fb';
  static const write = '0000ffe9-0000-1000-8000-00805f9a34fb';
}

/// Register writes, `FF AA <reg> <lo> <hi>`.
class WitCommands {
  static const setReturnRate200Hz = [0xFF, 0xAA, 0x03, 0x0B, 0x00];
  static const setBandwidth188Hz = [0xFF, 0xAA, 0x1F, 0x02, 0x00];
  static const calibrateAccelFlat = [0xFF, 0xAA, 0x01, 0x01, 0x00];
  static const readBattery = [0xFF, 0xAA, 0x27, 0x64, 0x00];

  /// Delay after enabling notifications before sending the rate and
  /// bandwidth writes.
  static const setupDelay = Duration(milliseconds: 750);
  static const batteryFirstPoll = Duration(milliseconds: 1500);
  static const batteryPollInterval = Duration(seconds: 30);
}

/// Something decoded from the notification byte stream.
sealed class WitEvent {}

class WitImuEvent extends WitEvent {
  WitImuEvent(this.sample);
  final SensorSample sample;
}

class WitBatteryEvent extends WitEvent {
  WitBatteryEvent(this.volts, this.percent);
  final double volts;
  final double percent;
}

/// Reassembles frames from BLE notifications, which can split or merge
/// frames arbitrarily.
///
/// Resyncs on header `0x55` followed by a known type byte, like the
/// reference app: `0x61` → 30-byte IMU frame, `0x71` → 20-byte register reply.
class WitFrameDecoder {
  static const _header = 0x55;
  static const _typeImu = 0x61;
  static const _typeRegister = 0x71;
  static const _imuLength = 30;
  static const _registerLength = 20;

  final _buffer = <int>[];

  /// Bytes discarded while searching for a frame header.
  int skippedBytes = 0;

  List<WitEvent> add(List<int> bytes, {int? hostTimeUs}) {
    final now = hostTimeUs ?? DateTime.now().microsecondsSinceEpoch;
    _buffer.addAll(bytes);
    final events = <WitEvent>[];
    while (_buffer.length >= 2) {
      final type = _buffer[1];
      if (_buffer[0] != _header || (type != _typeImu && type != _typeRegister)) {
        _buffer.removeAt(0);
        skippedBytes++;
        continue;
      }
      final length = type == _typeImu ? _imuLength : _registerLength;
      if (_buffer.length < length) break;
      final frame = Uint8List.fromList(_buffer.sublist(0, length));
      _buffer.removeRange(0, length);
      final event = type == _typeImu
          ? WitImuEvent(parseImuFrame(frame, hostTimeUs: now))
          : _parseRegisterFrame(frame);
      if (event != null) events.add(event);
    }
    return events;
  }

  void reset() {
    _buffer.clear();
    skippedBytes = 0;
  }

  static SensorSample parseImuFrame(Uint8List f, {required int hostTimeUs}) {
    final d = ByteData.sublistView(f);
    int16(int offset) => d.getInt16(offset, Endian.little);
    accel(int o) => int16(o) / 32768.0 * 16.0;
    gyro(int o) => int16(o) / 32768.0 * 2000.0;
    quat(int o) => int16(o) / 32768.0;
    return SensorSample(
      hostTimeUs: hostTimeUs,
      sensorTimeMs: chipTimeMs(f),
      ax: accel(10),
      ay: accel(12),
      az: accel(14),
      gx: gyro(16),
      gy: gyro(18),
      gz: gyro(20),
      q0: quat(22),
      q1: quat(24),
      q2: quat(26),
      q3: quat(28),
    );
  }

  /// Chip RTC in bytes 2–9 (YY MM DD hh mm ss, then ms as uint16 LE),
  /// returned as UTC epoch ms. Null if the fields are not a valid date.
  static int? chipTimeMs(Uint8List f) {
    final month = f[3], day = f[4], hour = f[5], minute = f[6], second = f[7];
    final ms = f[8] | (f[9] << 8);
    if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 ||
        minute > 59 || second > 59 || ms > 999) {
      return null;
    }
    return DateTime.utc(2000 + f[2], month, day, hour, minute, second, ms)
        .millisecondsSinceEpoch;
  }

  static WitEvent? _parseRegisterFrame(Uint8List f) {
    if (f[2] != 0x64) return null; // only the battery register is requested
    final volts = ByteData.sublistView(f).getInt16(4, Endian.little) / 100.0;
    return WitBatteryEvent(volts, batteryPercent(volts));
  }

  /// Step table used by the reference app for a single-cell LiPo.
  static double batteryPercent(double v) {
    const steps = [
      (3.96, 100.0), (3.93, 90.0), (3.87, 75.0), (3.82, 60.0),
      (3.79, 50.0), (3.77, 40.0), (3.73, 30.0), (3.70, 20.0),
      (3.68, 15.0), (3.50, 10.0), (3.40, 5.0),
    ];
    for (final (threshold, percent) in steps) {
      if (v > threshold) return percent;
    }
    return 0;
  }
}
