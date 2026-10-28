import '../sensor/orientation.dart';
import '../sensor/witmotion/witmotion_link.dart';
import '../sensor/witmotion/witmotion_mode.dart';
import 'preferences.dart';
import 'sensor_controller.dart';

/// The WitMotion stream mode the debug settings ask for.
WitStreamMode witModeFor(Preferences p) => p.clockMode
    ? WitClockMode(filter: TiltFilter(gains: p.tiltGains))
    : WitAnglesMode();

/// Saves the angles/clock choice and switches the connected sensor to it
/// without reconnecting. [preferences] null (tests) only switches.
Future<void> setClockMode(
    PreferencesStore? preferences, SensorController sensor, bool clock) async {
  final p = (preferences?.value ?? const Preferences()).copyWith(clockMode: clock);
  await preferences?.update(p);
  final link = sensor.link;
  if (link is WitMotionLink && (link.mode is WitClockMode) != clock) {
    await link.setMode(witModeFor(p));
  }
}

/// Saves the tilt filter gains and applies them to a clock-mode link's
/// filter straight away.
Future<void> setTiltGains(PreferencesStore? preferences,
    SensorController sensor, TiltGains gains) async {
  final link = sensor.link;
  if (link is WitMotionLink) {
    if (link.mode case final WitClockMode m) m.filter.gains = gains;
  }
  await preferences?.update(preferences.value.copyWith(tiltGains: gains));
}
