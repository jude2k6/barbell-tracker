import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../workout/file_log.dart';
import '../sensor_link.dart';
import '../sensor_sample.dart';
import 'witmotion_mode.dart';
import 'witmotion_protocol.dart';
import 'witmotion_stats.dart';

/// WitMotion BLE IMU over flutter_blue_plus, following the reference app's
/// connect sequence: subscribe to notify, wait 750 ms, set 200 Hz and 188 Hz
/// bandwidth, poll battery after 1.5 s and then every 30 s.
///
/// Unlike the reference app, every write is preceded by the unlock (stock
/// firmware ignores writes without it), and [mode]'s setup write goes first.
/// [mode] picks between the sensor's angles and its clock; [setMode]
/// switches while connected. On Android it also asks for high connection
/// priority, so more than one notification per ~40 ms can get through.
class WitMotionLink implements SensorLink {
  WitMotionLink(this.device, {WitStreamMode? mode})
      : _mode = mode ?? WitAnglesMode();

  final BluetoothDevice device;
  WitStreamMode _mode;
  static const _tag = 'WitMotion';

  WitStreamMode get mode => _mode;

  /// Per-notification counts for the diagnostics screen.
  final WitLinkStats stats = WitLinkStats();

  final _decoder = WitFrameDecoder();
  final _state = StreamController<LinkState>.broadcast();
  final _samples = StreamController<SensorSample>.broadcast();
  final _battery = StreamController<double?>.broadcast();

  BluetoothCharacteristic? _writeChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  Timer? _setupTimer;
  Timer? _batteryTimer;
  int? _loggedImuLength;

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
      mode.reset();
      stats.reset();
      _loggedImuLength = null;
      if (Platform.isAndroid) {
        try {
          await device.requestConnectionPriority(
              connectionPriorityRequest: ConnectionPriority.high);
        } catch (e) {
          AppLog.w(_tag, 'connection priority request failed', e);
        }
      }
      stats.mtu = device.mtuNow;
      AppLog.i(_tag, 'mtu=${stats.mtu}');
      AppLog.i(_tag, 'stream mode=${mode.name}');
      _notifySub = notifyChar.onValueReceived.listen(_onBytes);
      device.cancelWhenDisconnected(_notifySub!);
      await notifyChar.setNotifyValue(true);

      _setupTimer = Timer(WitCommands.setupDelay, () async {
        for (final command in [
          ...mode.setupCommands,
          WitCommands.setReturnRate200Hz,
          WitCommands.setBandwidth188Hz,
        ]) {
          await _writeUnlocked(command);
        }
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

  /// Switches what the frame carries without reconnecting: sends [next]'s
  /// setup write and decodes with it from now on. The few frames already in
  /// flight are read the new way, so expect a short glitch.
  Future<void> setMode(WitStreamMode next) async {
    if (identical(next, _mode)) return;
    next.reset();
    _mode = next;
    AppLog.i(_tag, 'stream mode=${next.name} (switched)');
    for (final command in next.setupCommands) {
      await _writeUnlocked(command);
    }
  }

  @override
  Future<void> calibrateFlat() => _writeUnlocked(WitCommands.calibrateAccelFlat);

  void _onBytes(List<int> bytes) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final frames = <WitImuFrame>[];
    for (final event in _decoder.add(bytes)) {
      switch (event) {
        case WitImuFrame():
          frames.add(event);
        case WitBatteryEvent(:final percent):
          _battery.add(percent);
      }
    }
    stats.skippedBytes = _decoder.skippedBytes;
    stats.mtu = device.mtuNow; // may be renegotiated after connect
    if (frames.isEmpty) return;
    stats.addNotification(
        bytes: bytes.length, frames: frames.length, arrivalUs: now);
    final length = _decoder.imuLength;
    if (length != null && length != _loggedImuLength) {
      _loggedImuLength = length;
      AppLog.i(_tag, 'IMU frame format=$length-byte mode=${mode.name}');
    }
    for (final sample in mode.samplesFrom(frames, now)) {
      _samples.add(sample);
    }
  }

  Future<void> _writeUnlocked(List<int> command) async {
    await _write(WitCommands.unlock);
    await Future<void>.delayed(WitCommands.writeSpacing);
    await _write(command);
    await Future<void>.delayed(WitCommands.writeSpacing);
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
