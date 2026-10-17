import 'package:flutter/widgets.dart';

import '../permissions/permission_service.dart';
import '../recording/recording.dart';
import '../video/video_settings.dart';
import '../workout/analysis_runner.dart';
import '../workout/preferences.dart';
import '../workout/saved_sensor.dart';
import '../workout/sensor_controller.dart';
import '../workout/session_store.dart';

/// App-wide services, provided once above the navigator.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.sensor,
    required this.sessions,
    required this.recordings,
    this.analyzer = analyzeInBackground,
    this.videoSettings,
    this.permissions,
    this.preferences,
    this.savedSensor,
    required super.child,
  });

  final SensorController sensor;
  final SessionStore sessions;
  final RecordingStore recordings;
  final SetAnalyzer analyzer;

  /// Video recording preferences; null disables video (e.g. in tests).
  final VideoSettingsStore? videoSettings;

  /// Permission and Bluetooth-radio state; null skips checks (tests).
  final PermissionService? permissions;

  /// App preferences; null uses the defaults and shows no first-run
  /// guides, which need somewhere to remember they were seen (tests).
  final PreferencesStore? preferences;

  /// The remembered sensor and its auto-reconnect; null disables it (tests).
  final SavedSensor? savedSensor;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this context');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope old) =>
      sensor != old.sensor ||
      sessions != old.sessions ||
      recordings != old.recordings ||
      analyzer != old.analyzer ||
      videoSettings != old.videoSettings ||
      permissions != old.permissions ||
      preferences != old.preferences ||
      savedSensor != old.savedSensor;
}
