/// WitMotion BLE IMU protocol, as used by the reference app.
///
/// See notes/android-apk-decompiled.md §1 for where each value comes from,
/// and notes/sensor-clock-problems.md for the stock 20-byte frame.
library;

import 'dart:typed_data';

/// GATT identifiers. Note the non-standard `…805f9a34fb` base on the
/// WitMotion service and characteristics.
class WitUuids {
  static const service = '0000ffe5-0000-1000-8000-00805f9a34fb';
  static const notify = '0000ffe4-0000-1000-8000-00805f9a34fb';
  static const write = '0000ffe9-0000-1000-8000-00805f9a34fb';
}

/// Register writes, `FF AA <reg> <lo> <hi>`.
class WitCommands {
  /// Newer firmware ignores register writes unless this comes first. The
  /// reference app never sends it; its custom firmware doesn't need it.
  static const unlock = [0xFF, 0xAA, 0x69, 0x88, 0xB5];
  static const setReturnRate200Hz = [0xFF, 0xAA, 0x03, 0x0B, 0x00];
  static const setBandwidth188Hz = [0xFF, 0xAA, 0x1F, 0x02, 0x00];
  static const calibrateAccelFlat = [0xFF, 0xAA, 0x01, 0x01, 0x00];
  static const readBattery = [0xFF, 0xAA, 0x27, 0x64, 0x00];

  /// Register 0x96 picks what the last 6 bytes of a 20-byte `55 61` frame
  /// carry: 0 = roll/pitch/yaw, 2 = uint32 ms counter. Undocumented; checked
  /// on a WT9011DCL (notes/sensor-clock-problems.md). Not saved to flash.
  static const outputAngles = [0xFF, 0xAA, 0x96, 0x00, 0x00];
  static const outputClock = [0xFF, 0xAA, 0x96, 0x02, 0x00];

  /// Delay after enabling notifications before sending the rate and
  /// bandwidth writes.
  static const setupDelay = Duration(milliseconds: 750);

  /// Gap between an unlock and its write, and between writes.
  static const writeSpacing = Duration(milliseconds: 100);
  static const batteryFirstPoll = Duration(milliseconds: 1500);
  static const batteryPollInterval = Duration(seconds: 30);
}

/// Something decoded from the notification byte stream.
sealed class WitEvent {}

/// One `55 61` IMU frame, before a `WitStreamMode` turns it into a sample.
///
/// Two layouts exist. The stock 20-byte frame carries accel, gyro and a
/// 6-byte [tail] whose meaning depends on register 0x96. The reference
/// app's custom firmware sends a 30-byte frame with the chip clock and a
/// quaternion instead.
class WitImuFrame extends WitEvent {
  WitImuFrame({
    required this.ax, required this.ay, required this.az,
    required this.gx, required this.gy, required this.gz,
    this.tail,
    this.chipTimeMs,
    this.quaternion,
  });

  /// Acceleration in g and angular rate in deg/s, sensor frame.
  final double ax, ay, az, gx, gy, gz;

  /// 20-byte frames: bytes 14–19. Null on 30-byte frames.
  final Uint8List? tail;

  /// 30-byte frames: chip RTC as UTC epoch ms, null if it isn't a valid date.
  final int? chipTimeMs;

  /// 30-byte frames: quaternion w, x, y, z. Null on 20-byte frames.
  final (double, double, double, double)? quaternion;

  bool get isExtended => quaternion != null;
}

class WitBatteryEvent extends WitEvent {
  WitBatteryEvent(this.volts, this.percent);
  final double volts;
  final double percent;
}

/// Reassembles frames from BLE notifications, which can split or merge
/// frames arbitrarily (from 50 Hz up the sensor packs several per
/// notification).
///
/// Resyncs on header `0x55` followed by a known type byte: `0x61` → IMU
/// frame, `0x71` → 20-byte register reply. The IMU frame length (20 stock,
/// 30 for the reference app's firmware) is detected from where the next
/// header falls, then kept until the stream stops lining up.
class WitFrameDecoder {
  static const _header = 0x55;
  static const _typeImu = 0x61;
  static const _typeRegister = 0x71;
  static const standardImuLength = 20;
  static const extendedImuLength = 30;
  static const _registerLength = 20;

  final _buffer = <int>[];

  /// Bytes discarded while searching for a frame header.
  int skippedBytes = 0;

  /// IMU frame length in use, null until detected.
  int? imuLength;

  List<WitEvent> add(List<int> bytes) {
    _buffer.addAll(bytes);
    final events = <WitEvent>[];
    while (_buffer.length >= 2) {
      if (!_isHeaderAt(0)) {
        _skip();
        continue;
      }
      final int length;
      if (_buffer[1] == _typeRegister) {
        length = _registerLength;
      } else {
        final detected = imuLength ?? _detectImuLength();
        if (detected == null) break; // wait for more bytes
        if (detected == 0) {
          _skip();
          continue;
        }
        length = detected;
      }
      if (_buffer.length < length) break;
      final frame = Uint8List.fromList(_buffer.sublist(0, length));
      _buffer.removeRange(0, length);
      final WitEvent? event;
      if (frame[1] == _typeImu) {
        imuLength = length;
        event = length == extendedImuLength
            ? parseExtendedFrame(frame)
            : parseStandardFrame(frame);
      } else {
        event = _parseRegisterFrame(frame);
      }
      if (event != null) events.add(event);
      // Next bytes not a header: the length guess was wrong; detect again.
      if (_buffer.length >= 2 && !_isHeaderAt(0)) imuLength = null;
    }
    return events;
  }

  void reset() {
    _buffer.clear();
    skippedBytes = 0;
    imuLength = null;
  }

  void _skip() {
    _buffer.removeAt(0);
    skippedBytes++;
  }

  bool _isHeaderAt(int i) =>
      _buffer.length >= i + 2 &&
      _buffer[i] == _header &&
      (_buffer[i + 1] == _typeImu || _buffer[i + 1] == _typeRegister);

  /// 20 or 30 if the next header sits there (confirmed by the one after
  /// when buffered), 0 if neither can, null if more bytes are needed.
  int? _detectImuLength() {
    bool fits(int len) =>
        _isHeaderAt(len) &&
        (_buffer.length < 2 * len + 2 || _isHeaderAt(2 * len));
    if (_buffer.length >= standardImuLength + 2 && fits(standardImuLength)) {
      return standardImuLength;
    }
    if (_buffer.length >= extendedImuLength + 2 && fits(extendedImuLength)) {
      return extendedImuLength;
    }
    return _buffer.length >= 2 * extendedImuLength + 2 ? 0 : null;
  }

  static WitImuFrame parseStandardFrame(Uint8List f) {
    final d = ByteData.sublistView(f);
    double accel(int o) => d.getInt16(o, Endian.little) / 32768.0 * 16.0;
    double gyro(int o) => d.getInt16(o, Endian.little) / 32768.0 * 2000.0;
    return WitImuFrame(
      ax: accel(2), ay: accel(4), az: accel(6),
      gx: gyro(8), gy: gyro(10), gz: gyro(12),
      tail: Uint8List.fromList(f.sublist(14, 20)),
    );
  }

  static WitImuFrame parseExtendedFrame(Uint8List f) {
    final d = ByteData.sublistView(f);
    double accel(int o) => d.getInt16(o, Endian.little) / 32768.0 * 16.0;
    double gyro(int o) => d.getInt16(o, Endian.little) / 32768.0 * 2000.0;
    double quat(int o) => d.getInt16(o, Endian.little) / 32768.0;
    return WitImuFrame(
      ax: accel(10), ay: accel(12), az: accel(14),
      gx: gyro(16), gy: gyro(18), gz: gyro(20),
      chipTimeMs: chipTimeMs(f),
      quaternion: (quat(22), quat(24), quat(26), quat(28)),
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
