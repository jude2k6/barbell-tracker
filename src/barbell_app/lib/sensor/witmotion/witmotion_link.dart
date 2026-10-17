import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../sensor_link.dart';
import '../sensor_sample.dart';
import 'witmotion_protocol.dart';

/// WitMotion BLE IMU over flutter_blue_plus, following the reference app's
/// connect sequence: subscribe to notify, wait 750 ms, set 200 Hz and 188 Hz
/// bandwidth, poll battery after 1.5 s and then every 30 s.
class WitMotionLink implements SensorLink {
  WitMotionLink(this.device);

  final BluetoothDevice device;

  final _decoder = WitFrameDecoder();
  final _state = StreamController<LinkState>.broadcast();
  final _samples = StreamController<SensorSample>.broadcast();
  final _battery = StreamController<double?>.broadcast();

  BluetoothCharacteristic? _writeChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  Timer? _setupTimer;
  Timer? _batteryTimer;

  @override
  String get name => device.platformName.isNotEmpty
      ? device.platformName
      : device.remoteId.str;

  @override
  String get id => device.remoteId.str;

  @override
  Stream<LinkState> get state => _state.stream;

  @override
  Stream<SensorSample> get samples => _samples.stream;

  @override
  Stream<double?> get batteryPercent => _battery.stream;

  @override
  Future<void> connect() async {
    _state.add(LinkState.connecting);
    try {
      // Personal, non-commercial use under the FlutterBluePlus license.
      await device.connect(license: License.nonprofit);
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _onDisconnected();
      });

      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid == Guid(WitUuids.service),
        orElse: () => throw StateError('WitMotion service not found'),
      );
      BluetoothCharacteristic find(String uuid) =>
          service.characteristics.firstWhere(
            (c) => c.uuid == Guid(uuid),
            orElse: () => throw StateError('Characteristic $uuid not found'),
          );
      final notifyChar = find(WitUuids.notify);
      _writeChar = find(WitUuids.write);

      _decoder.reset();
      _notifySub = notifyChar.onValueReceived.listen(_onBytes);
      device.cancelWhenDisconnected(_notifySub!);
      await notifyChar.setNotifyValue(true);

      _setupTimer = Timer(WitCommands.setupDelay, () async {
        await _write(WitCommands.setReturnRate200Hz);
        await _write(WitCommands.setBandwidth188Hz);
      });
      _batteryTimer = Timer(WitCommands.batteryFirstPoll, () {
        _write(WitCommands.readBattery);
        _batteryTimer = Timer.periodic(
          WitCommands.batteryPollInterval,
          (_) => _write(WitCommands.readBattery),
        );
      });
      _state.add(LinkState.streaming);
    } catch (e) {
      debugPrint('WitMotion connect failed: $e');
      _state.add(LinkState.failed);
      await device.disconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _cancelTimers();
    await device.disconnect();
  }

  @override
  Future<void> calibrateFlat() => _write(WitCommands.calibrateAccelFlat);

  void _onBytes(List<int> bytes) {
    for (final event in _decoder.add(bytes)) {
      switch (event) {
        case WitImuEvent(:final sample):
          _samples.add(sample);
        case WitBatteryEvent(:final percent):
          _battery.add(percent);
      }
    }
  }

  Future<void> _write(List<int> command) async {
    final c = _writeChar;
    if (c == null || device.isDisconnected) return;
    try {
      await c.write(command); // with response, like the reference app
    } catch (e) {
      debugPrint('WitMotion write failed: $e');
    }
  }

  void _onDisconnected() {
    _cancelTimers();
    _writeChar = null;
    _connSub?.cancel();
    _connSub = null;
    _battery.add(null);
    _state.add(LinkState.disconnected);
  }

  void _cancelTimers() {
    _setupTimer?.cancel();
    _batteryTimer?.cancel();
  }
}
