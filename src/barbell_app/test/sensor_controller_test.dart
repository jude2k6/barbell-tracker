import 'package:barbell_app/sensor/sensor_link.dart';
import 'package:barbell_app/workout/sensor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sensor_link.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('connects, mirrors battery, forwards samples and keeps a trace', () async {
    final c = SensorController(traceLength: 4);
    final link = FakeSensorLink();
    final received = <double>[];
    c.samples.listen((s) => received.add(s.az));

    await c.connect(link);
    expect(c.isStreaming, isTrue);
    link.battery(77);
    expect(c.batteryPercent, 77);

    for (var i = 0; i < 6; i++) {
      link.emit(i, az: 1.0 + i / 10);
    }
    await settle();
    expect(received, hasLength(6));
    final trace = c.traceSnapshot();
    expect(trace, hasLength(4));
    expect(trace.first, closeTo(0.2, 1e-9)); // oldest kept: i = 2
    expect(trace.last, closeTo(0.5, 1e-9));
    expect(c.rate.received, 6);
    c.dispose();
  });

  test('reconnects after an unexpected drop', () async {
    final c = SensorController(reconnectDelays: const [Duration.zero, Duration.zero]);
    final link = FakeSensorLink();
    await c.connect(link);
    link.drop();
    expect(c.reconnecting, isTrue);
    await settle();
    expect(link.connectCalls, 2);
    expect(c.isStreaming, isTrue);
    expect(c.reconnecting, isFalse);
    c.dispose();
  });

  test('gives up after the last reconnect attempt', () async {
    final c = SensorController(reconnectDelays: const [Duration.zero, Duration.zero]);
    final link = FakeSensorLink();
    await c.connect(link);
    link.failConnects = 99;
    link.drop();
    await settle();
    expect(link.connectCalls, 3); // initial + two retries
    expect(c.isStreaming, isFalse);
    expect(c.reconnecting, isFalse);
    c.dispose();
  });

  test('user disconnect does not reconnect', () async {
    final c = SensorController(reconnectDelays: const [Duration.zero]);
    final link = FakeSensorLink();
    await c.connect(link);
    await c.disconnect();
    await settle();
    expect(link.connectCalls, 1);
    expect(link.disconnectCalls, 1);
    expect(c.link, isNull);
    expect(c.state, LinkState.disconnected);
    c.dispose();
  });

  test('initial connect failure is reported, not retried', () async {
    final c = SensorController(reconnectDelays: const [Duration.zero]);
    final link = FakeSensorLink(failConnects: 1);
    await c.connect(link);
    await settle();
    expect(link.connectCalls, 1);
    expect(c.state, LinkState.failed);
    expect(c.lastError, isA<StateError>());
    c.dispose();
  });
}
