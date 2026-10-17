import 'dart:async';

import 'package:flutter/foundation.dart';

import '../sensor/rate_monitor.dart';
import '../sensor/sensor_link.dart';
import '../sensor/sensor_sample.dart';
import 'file_log.dart';

/// The one sensor shared by the whole app.
///
/// Owns the active [SensorLink], mirrors its state and battery, measures the
/// delivered rate, keeps a short vertical-acceleration trace for live plots,
/// and re-broadcasts samples on [samples] so listeners survive reconnects.
///
/// If a link that was streaming drops unexpectedly, it reconnects with
/// backoff ([reconnecting] is true meanwhile). [disconnect] stops that.
class SensorController extends ChangeNotifier {
  SensorController({
    this.traceLength = 800,
    this.reconnectDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
    ],
  }) : _trace = Float64List(traceLength);

  /// Samples kept for the live trace (800 = 4 s at 200 Hz).
  final int traceLength;

  /// Waits before each reconnect attempt; attempts stop after the last.
  final List<Duration> reconnectDelays;

  static const _tag = 'BleCoordinator';

  final RateMonitor rate = RateMonitor();

  /// Bumped on every sample; use as a painter's `repaint` listenable so the
  /// trace redraws at most once per frame without rebuilding widgets.
  final ValueNotifier<int> traceTick = ValueNotifier(0);

  final Float64List _trace;
  int _traceCount = 0;
  int _traceHead = 0;

  final _samples = StreamController<SensorSample>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];

  SensorLink? _link;
  LinkState _state = LinkState.disconnected;
  double? _battery;
  bool _wanted = false;
  bool _everStreamed = false;
  bool _connecting = false;
  int _attempt = 0;
  Timer? _reconnectTimer;
  Object? _lastError;

  SensorLink? get link => _link;
  LinkState get state => _state;
  double? get batteryPercent => _battery;
  bool get isStreaming => _state == LinkState.streaming;
  bool get reconnecting => _reconnectTimer != null || (_connecting && _everStreamed);
  Object? get lastError => _lastError;

  /// Every sample from the current (or any future) link.
  Stream<SensorSample> get samples => _samples.stream;

  /// Live trace, oldest first: world-Z acceleration in g, gravity removed.
  List<double> traceSnapshot() {
    final out = List<double>.filled(_traceCount, 0);
    final start = (_traceHead - _traceCount) % traceLength;
    for (var i = 0; i < _traceCount; i++) {
      out[i] = _trace[(start + i) % traceLength];
    }
    return out;
  }

  /// Connects [link], replacing any current link.
  Future<void> connect(SensorLink link) async {
    if (!identical(link, _link)) {
      await _detach(disconnectLink: true);
      _state = LinkState.disconnected;
      _battery = null;
      _link = link;
      _subs
        ..add(link.state.listen(_onState))
        ..add(link.batteryPercent.listen((b) {
          _battery = b;
          notifyListeners();
        }))
        ..add(link.samples.listen(_onSample));
    }
    AppLog.i(_tag, 'connect name=${link.name} id=${link.id}');
    _wanted = true;
    _everStreamed = false;
    _attempt = 0;
    _lastError = null;
    _clearTrace();
    rate.reset();
    await _connectOnce();
  }

  /// Disconnects and forgets the link; no automatic reconnect.
  Future<void> disconnect() async {
    AppLog.i(_tag, 'disconnect requested name=${_link?.name}');
    _wanted = false;
    await _detach(disconnectLink: true);
    _state = LinkState.disconnected;
    _battery = null;
    notifyListeners();
  }

  Future<void> calibrateFlat() async => _link?.calibrateFlat();

  Future<void> _connectOnce() async {
    final link = _link;
    if (link == null) return;
    _connecting = true;
    notifyListeners();
    try {
      await link.connect();
      _lastError = null;
    } catch (e) {
      _lastError = e;
      AppLog.w(_tag, 'connect failed name=${link.name}', e);
      if (!identical(link, _link)) return;
      if (_state != LinkState.failed) _state = LinkState.failed;
    } finally {
      _connecting = false;
    }
    if (!identical(link, _link)) return;
    if (_state != LinkState.streaming) _scheduleReconnect();
    notifyListeners();
  }

  void _onState(LinkState s) {
    if (s != _state) AppLog.i(_tag, 'state ${_state.name} -> ${s.name}');
    _state = s;
    if (s == LinkState.streaming) {
      _everStreamed = true;
      _attempt = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    } else if (s == LinkState.disconnected && !_connecting) {
      _scheduleReconnect();
    }
    notifyListeners();
  }

  void _scheduleReconnect() {
    if (!_wanted || !_everStreamed || _connecting) return;
    if (_reconnectTimer != null) return;
    if (_attempt >= reconnectDelays.length) {
      AppLog.w(_tag, 'reconnect gave up after $_attempt attempts');
      _wanted = false;
      return;
    }
    final delay = reconnectDelays[_attempt++];
    AppLog.i(_tag, 'reconnect attempt $_attempt in ${delay.inSeconds}s');
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_wanted) _connectOnce();
    });
  }

  void _onSample(SensorSample s) {
    rate.add(s);
    _trace[_traceHead] = s.worldZ - 1.0;
    _traceHead = (_traceHead + 1) % traceLength;
    if (_traceCount < traceLength) _traceCount++;
    _samples.add(s);
    traceTick.value++;
  }

  void _clearTrace() {
    _traceCount = 0;
    _traceHead = 0;
    traceTick.value++;
  }

  Future<void> _detach({required bool disconnectLink}) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final link = _link;
    _link = null;
    if (disconnectLink && link != null) {
      try {
        await link.disconnect();
      } catch (e) {
        debugPrint('Sensor disconnect failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _wanted = false;
    _detach(disconnectLink: true);
    _samples.close();
    traceTick.dispose();
    super.dispose();
  }
}
