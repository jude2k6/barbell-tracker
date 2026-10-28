/// How a WitMotion sensor's stock 20-byte frames become samples.
///
/// The stock frame has room for either the sensor's angles or its
/// millisecond clock, not both (register 0x96). Each [WitStreamMode] picks
/// one, sends the matching setup write and fills in what's missing. See
/// notes/sensor-clock-problems.md for the trade-offs.
library;

import 'dart:typed_data';

import '../orientation.dart';
import '../sensor_sample.dart';
import 'witmotion_protocol.dart';

abstract class WitStreamMode {
  /// Short name for the debug log.
  String get name;

  /// Register writes sent at connect, each after an unlock, before the rate
  /// and bandwidth writes.
  List<List<int>> get setupCommands;

  /// Turns the IMU frames decoded from one notification, which arrived at
  /// [hostTimeUs], into samples.
  List<SensorSample> samplesFrom(List<WitImuFrame> frames, int hostTimeUs);

  /// Forget timing and orientation state, e.g. on reconnect.
  void reset();
}

/// Keeps the sensor's roll/pitch/yaw (0x96 = 0) and rebuilds sample times
/// from notification arrivals, since the frame has no clock. Samples carry
/// no [SensorSample.sensorTimeMs].
class WitAnglesMode implements WitStreamMode {
  WitAnglesMode({int nominalHz = 200})
      : _clock = NotificationClock(nominalPeriodUs: 1e6 / nominalHz);

  final NotificationClock _clock;

  @override
  String get name => 'angles';

  @override
  List<List<int>> get setupCommands => const [WitCommands.outputAngles];

  @override
  List<SensorSample> samplesFrom(List<WitImuFrame> frames, int hostTimeUs) {
    final standard = frames.where((f) => !f.isExtended).toList();
    final times = _clock.stamp(standard.length, hostTimeUs);
    var i = 0;
    return [
      for (final f in frames)
        if (f.isExtended)
          extendedSample(f, hostTimeUs)
        else
          _sample(f, times[i++]),
    ];
  }

  SensorSample _sample(WitImuFrame f, int hostTimeUs) {
    final d = ByteData.sublistView(f.tail!);
    double angle(int o) => d.getInt16(o, Endian.little) / 32768.0 * 180.0;
    final (w, x, y, z) = eulerToQuaternion(angle(0), angle(2), angle(4));
    return _withQuaternion(f, hostTimeUs, null, w, x, y, z);
  }

  @override
  void reset() => _clock.reset();
}

/// Switches the frame to the sensor's ms counter (0x96 = 2) for real
/// per-sample times, and computes orientation with a [TiltFilter] since the
/// angles are gone. The counter runs from power-on; it is not wall time.
class WitClockMode implements WitStreamMode {
  WitClockMode({TiltFilter? filter, this.nominalHz = 200})
      : filter = filter ?? TiltFilter();

  /// Its gains can be changed while streaming.
  final TiltFilter filter;
  final double nominalHz;
  int? _lastMs;

  /// Longest counter step integrated as-is; longer gaps (lost frames) use
  /// one nominal period so the filter doesn't jump.
  static const _maxStepMs = 100;

  @override
  String get name => 'clock';

  @override
  List<List<int>> get setupCommands => const [WitCommands.outputClock];

  @override
  List<SensorSample> samplesFrom(List<WitImuFrame> frames, int hostTimeUs) => [
        for (final f in frames)
          f.isExtended ? extendedSample(f, hostTimeUs) : _sample(f, hostTimeUs),
      ];

  SensorSample _sample(WitImuFrame f, int hostTimeUs) {
    final ms = ByteData.sublistView(f.tail!).getUint32(0, Endian.little);
    final last = _lastMs;
    final step = last == null ? 0 : ms - last;
    final dt = step > 0 && step <= _maxStepMs ? step / 1000 : 1 / nominalHz;
    _lastMs = ms;
    filter.update(
      ax: f.ax, ay: f.ay, az: f.az, gx: f.gx, gy: f.gy, gz: f.gz, dt: dt,
    );
    return _withQuaternion(
        f, hostTimeUs, ms, filter.q0, filter.q1, filter.q2, filter.q3);
  }

  @override
  void reset() {
    _lastMs = null;
    filter.reset();
  }
}

/// A 30-byte frame already has the chip clock and quaternion; every mode
/// passes it through unchanged.
SensorSample extendedSample(WitImuFrame f, int hostTimeUs) {
  final (w, x, y, z) = f.quaternion!;
  return _withQuaternion(f, hostTimeUs, f.chipTimeMs, w, x, y, z);
}

SensorSample _withQuaternion(WitImuFrame f, int hostTimeUs, int? sensorTimeMs,
        double w, double x, double y, double z) =>
    SensorSample(
      hostTimeUs: hostTimeUs,
      sensorTimeMs: sensorTimeMs,
      ax: f.ax, ay: f.ay, az: f.az,
      gx: f.gx, gy: f.gy, gz: f.gz,
      q0: w, q1: x, q2: y, q3: z,
    );

/// Spreads the frames of each notification evenly over the time since the
/// previous one, so packed frames don't share an arrival time.
///
/// A notification that comes more than 1.5 periods per frame late is taken
/// as a gap (lost or delayed packets): its frames are placed one period
/// apart, ending at its arrival, which leaves the hole visible. The period
/// estimate follows the arrivals, so it adapts to the rate actually set;
/// several gaps in a row mean the rate dropped, and become the new period.
class NotificationClock {
  NotificationClock({this.nominalPeriodUs = 5000});

  final double nominalPeriodUs;
  double? _periodUs;
  int? _lastUs;
  int _gapRun = 0;

  static const _gapFactor = 1.5;
  static const _gapsForNewRate = 3;
  static const _smoothing = 0.1;

  /// Host times in µs for [count] frames that arrived together at
  /// [arrivalUs], oldest first. Strictly increasing across calls.
  List<int> stamp(int count, int arrivalUs) {
    if (count == 0) return const [];
    final last = _lastUs;
    final period = _periodUs ?? nominalPeriodUs;
    final List<int> times;
    final perFrame = last == null ? null : (arrivalUs - last) / count;
    if (last == null || perFrame! > _gapFactor * period) {
      times = [
        for (var i = 0; i < count; i++)
          arrivalUs - ((count - 1 - i) * period).round(),
      ];
      if (last != null && (_periodUs == null || ++_gapRun >= _gapsForNewRate)) {
        _periodUs = perFrame;
        _gapRun = 0;
      }
    } else {
      _gapRun = 0;
      times = [
        for (var i = 1; i <= count; i++)
          arrivalUs > last + count
              ? last + ((arrivalUs - last) * i / count).round()
              : last + i, // arrived together: keep times increasing
      ];
      _periodUs = _periodUs == null
          ? perFrame
          : period + _smoothing * (perFrame - period);
    }
    if (last != null && times.first <= last) {
      // A gap shorter than the frames' span: shift past the previous stamp.
      final shift = last + 1 - times.first;
      for (var i = 0; i < count; i++) {
        times[i] += shift;
      }
    }
    _lastUs = times.last;
    return times;
  }

  void reset() {
    _periodUs = null;
    _lastUs = null;
    _gapRun = 0;
  }
}
