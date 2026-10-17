import 'dart:async';

import 'package:barbell_app/sensor/sensor_link.dart';
import 'package:barbell_app/sensor/sensor_sample.dart';

/// In-memory [SensorLink] for tests.
class FakeSensorLink implements SensorLink {
  FakeSensorLink({this.failConnects = 0, this.id = 'AA:BB:CC:DD:EE:FF'});

  @override
  final String id;

  /// Number of upcoming connect() calls that should fail.
  int failConnects;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int calibrations = 0;

  final _state = StreamController<LinkState>.broadcast(sync: true);
  final _samples = StreamController<SensorSample>.broadcast(sync: true);
  final _battery = StreamController<double?>.broadcast(sync: true);

  @override
  String get name => 'Fake';

  @override
  Stream<LinkState> get state => _state.stream;

  @override
  Stream<SensorSample> get samples => _samples.stream;

  @override
  Stream<double?> get batteryPercent => _battery.stream;

  @override
  Future<void> connect() async {
    connectCalls++;
    _state.add(LinkState.connecting);
    if (failConnects > 0) {
      failConnects--;
      _state.add(LinkState.failed);
      throw StateError('connect failed');
    }
    _state.add(LinkState.streaming);
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    _state.add(LinkState.disconnected);
  }

  @override
  Future<void> calibrateFlat() async => calibrations++;

  /// Simulates the radio link dropping.
  void drop() => _state.add(LinkState.disconnected);

  void battery(double? pct) => _battery.add(pct);

  void emit(int i, {double az = 1.0}) => _samples.add(SensorSample(
        hostTimeUs: i * 5000,
        sensorTimeMs: i * 5,
        ax: 0, ay: 0, az: az,
        gx: 0, gy: 0, gz: 0,
        q0: 1, q1: 0, q2: 0, q3: 0,
      ));
}
