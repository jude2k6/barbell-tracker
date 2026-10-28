import 'dart:math' as math;

/// What arrives over BLE, one entry per notification, for the diagnostics
/// screen: how big notifications are, how many frames each packs, and how
/// far apart they come. Answers whether the phone gets the sensor's 200 Hz
/// or one frame per ~40 ms connection event (notes/sensor-clock-problems.md).
class WitLinkStats {
  /// Arrival gaps kept for the mean / p95 / max.
  static const gapWindow = 500;

  int notifications = 0;
  int frames = 0;

  /// Notification length in bytes → count. Multiples of 20 above 20 mean
  /// the sensor packs frames.
  final Map<int, int> notificationLengths = {};

  /// IMU frames decoded from one notification → count.
  final Map<int, int> framesPerNotification = {};

  /// Negotiated MTU, null until known.
  int? mtu;

  /// Bytes the decoder threw away looking for a header.
  int skippedBytes = 0;

  int? _lastArrivalUs;
  final List<int> _gapsUs = [];

  void addNotification(
      {required int bytes, required int frames, required int arrivalUs}) {
    notifications++;
    this.frames += frames;
    notificationLengths.update(bytes, (n) => n + 1, ifAbsent: () => 1);
    framesPerNotification.update(frames, (n) => n + 1, ifAbsent: () => 1);
    final last = _lastArrivalUs;
    if (last != null) {
      _gapsUs.add(arrivalUs - last);
      if (_gapsUs.length > gapWindow) _gapsUs.removeAt(0);
    }
    _lastArrivalUs = arrivalUs;
  }

  /// Recent gaps between notifications in ms: mean, 95th percentile, max.
  /// Null before two notifications.
  ({double mean, double p95, double max})? get gapsMs {
    if (_gapsUs.isEmpty) return null;
    final sorted = [..._gapsUs]..sort();
    final mean = sorted.fold(0, (a, g) => a + g) / sorted.length;
    final p95 = sorted[math.min(sorted.length - 1, (sorted.length * 0.95).floor())];
    return (mean: mean / 1000, p95: p95 / 1000, max: sorted.last / 1000);
  }

  void reset() {
    notifications = 0;
    frames = 0;
    notificationLengths.clear();
    framesPerNotification.clear();
    skippedBytes = 0;
    _lastArrivalUs = null;
    _gapsUs.clear();
  }
}
