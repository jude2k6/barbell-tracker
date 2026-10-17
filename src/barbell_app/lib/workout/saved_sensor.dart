import 'dart:async';

import '../sensor/sensor_link.dart';
import 'preferences.dart';
import 'sensor_controller.dart';

/// Looks for the BLE device [id] for up to [timeout] and returns a link to
/// it, or null if it did not show up.
typedef SensorFinder = Future<SensorLink?> Function(String id, Duration timeout);

/// The last connected sensor, remembered and reconnected to automatically
/// (Stance's `BleLastDeviceStore` and `AutoReconnectToLastSavedBleDeviceUseCase`).
///
/// - The sensor's address is saved in [Preferences.savedSensorId] once a
///   connection is streaming. A user disconnect keeps it; only [forget] (the
///   Device screen's "Forget saved device") clears it.
/// - [autoConnect] runs when Home or the Device screen opens. It tries once
///   per app run: scan for the saved sensor for up to [scanTimeout]
///   (Stance: 12 s), connect if seen, give up silently if not. There is no
///   retry or backoff; the usual reconnect of a link that dropped is
///   [SensorController]'s.
class SavedSensor {
  SavedSensor({
    required this.sensor,
    required this.preferences,
    required this.find,
    this.scanTimeout = const Duration(seconds: 12),
    Future<void>? preferencesLoaded,
  }) : _loaded = preferencesLoaded ?? Future.value() {
    sensor.addListener(_onSensor);
  }

  final SensorController sensor;
  final PreferencesStore preferences;
  final SensorFinder find;
  final Duration scanTimeout;
  final Future<void> _loaded;

  bool _attempted = false;

  String? get savedId => preferences.value.savedSensorId;
  bool get hasSaved => savedId != null && savedId!.trim().isNotEmpty;

  /// Reconnects to the saved sensor if nothing is connected. [permitted] is
  /// whether Bluetooth can be used right now; without it nothing happens and
  /// the one attempt is kept for later. Returns true if it connected.
  Future<bool> autoConnect({required bool permitted}) async {
    if (!permitted || _attempted) return false;
    if (sensor.link != null || sensor.state != LinkState.disconnected) return false;
    _attempted = true;
    await _loaded;
    final id = savedId;
    if (id == null || id.trim().isEmpty) return false;
    final SensorLink? link;
    try {
      link = await find(id, scanTimeout);
    } catch (_) {
      return false;
    }
    // The user may have connected something by hand while scanning.
    if (link == null || sensor.link != null) return false;
    await sensor.connect(link);
    return sensor.isStreaming;
  }

  /// Disconnects and removes the saved sensor, so a different one can be
  /// paired.
  Future<void> forget() async {
    await sensor.disconnect();
    await preferences.update(preferences.value.copyWith(forgetSavedSensor: true));
  }

  void _onSensor() {
    final link = sensor.link;
    if (link == null || !sensor.isStreaming || link.id == savedId) return;
    preferences.update(preferences.value.copyWith(savedSensorId: link.id));
  }

  void dispose() => sensor.removeListener(_onSensor);
}
