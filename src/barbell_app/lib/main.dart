import 'package:flutter/material.dart';

import 'permissions/permission_service.dart';
import 'recording/recording.dart';
import 'ui/app_scope.dart';
import 'sensor/witmotion/witmotion_scan.dart';
import 'ui/home_page.dart';
import 'ui/stance_theme.dart';
import 'video/video_settings.dart';
import 'workout/file_log.dart';
import 'workout/preferences.dart';
import 'workout/saved_sensor.dart';
import 'workout/sensor_controller.dart';
import 'workout/session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLog.init();
  runApp(const BarbellApp());
}

/// Root widget: creates the app-wide services and the themed shell.
class BarbellApp extends StatefulWidget {
  const BarbellApp({super.key});

  @override
  State<BarbellApp> createState() => _BarbellAppState();
}

class _BarbellAppState extends State<BarbellApp> {
  final _sensor = SensorController();
  final _sessions = SessionStore();
  final _recordings = RecordingStore();
  final _videoSettings = VideoSettingsStore()..load();
  final _permissions = PermissionService();
  final _preferences = PreferencesStore();
  late final SavedSensor _savedSensor;

  @override
  void initState() {
    super.initState();
    _savedSensor = SavedSensor(
      sensor: _sensor,
      preferences: _preferences,
      find: findWitMotion,
      preferencesLoaded: _preferences.load(),
    );
  }

  @override
  void dispose() {
    _savedSensor.dispose();
    _sensor.dispose();
    _sessions.dispose();
    _videoSettings.dispose();
    _permissions.dispose();
    _preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      sensor: _sensor,
      sessions: _sessions,
      recordings: _recordings,
      videoSettings: _videoSettings,
      permissions: _permissions,
      preferences: _preferences,
      savedSensor: _savedSensor,
      child: MaterialApp(
        title: 'Barbell Tracker',
        // Stance is dark-only.
        theme: stanceTheme(),
        home: const HomePage(),
      ),
    );
  }
}
