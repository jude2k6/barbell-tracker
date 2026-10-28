import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../sensor/orientation.dart';
import 'session.dart';
import 'user_profile.dart';

/// App preferences. Stance's Preferences screen (weight unit for weight
/// input, height unit), the User Details profile, and its "has seen" flags
/// for one-time guides.
@immutable
class Preferences {
  const Preferences({
    this.weightUnit = WeightUnit.kg,
    this.heightUnit = HeightUnit.cm,
    this.profile = const UserProfile(),
    this.seenGuides = const {},
    this.savedSensorId,
    this.clockMode = false,
    this.tiltGains = const TiltGains(),
  });

  factory Preferences.fromJson(Map<String, dynamic> j) => Preferences(
        weightUnit: WeightUnit.fromName(j['weightUnit'] as String?),
        heightUnit: HeightUnit.fromName(j['heightUnit'] as String?),
        profile: switch (j['profile']) {
          final Map<String, dynamic> p => UserProfile.fromJson(p),
          _ => const UserProfile(),
        },
        seenGuides: {
          for (final g in (j['seenGuides'] as List? ?? const [])) g as String,
        },
        savedSensorId: j['savedSensorId'] as String?,
        clockMode: j['clockMode'] as bool? ?? false,
        tiltGains: switch (j['tiltGains']) {
          final Map<String, dynamic> g => TiltGains.fromJson(g),
          _ => const TiltGains(),
        },
      );

  final WeightUnit weightUnit;
  final HeightUnit heightUnit;
  final UserProfile profile;

  /// [Guide] names already shown.
  final Set<String> seenGuides;

  /// Address of the last sensor that connected (Stance's `BleLastDeviceStore`),
  /// reconnected to automatically. Null when none or forgotten.
  final String? savedSensorId;

  /// Debug: stream the sensor's ms counter and compute orientation in the
  /// app (WitClockMode) instead of using the sensor's angles.
  final bool clockMode;

  /// Debug: gains for the app's own tilt filter, tuned on the diagnostics
  /// screen.
  final TiltGains tiltGains;

  Preferences copyWith({
    WeightUnit? weightUnit,
    HeightUnit? heightUnit,
    UserProfile? profile,
    Set<String>? seenGuides,
    String? savedSensorId,
    bool forgetSavedSensor = false,
    bool? clockMode,
    TiltGains? tiltGains,
  }) =>
      Preferences(
        weightUnit: weightUnit ?? this.weightUnit,
        heightUnit: heightUnit ?? this.heightUnit,
        profile: profile ?? this.profile,
        seenGuides: seenGuides ?? this.seenGuides,
        savedSensorId:
            forgetSavedSensor ? null : savedSensorId ?? this.savedSensorId,
        clockMode: clockMode ?? this.clockMode,
        tiltGains: tiltGains ?? this.tiltGains,
      );

  Map<String, dynamic> toJson() => {
        'weightUnit': weightUnit.name,
        'heightUnit': heightUnit.name,
        'profile': profile.toJson(),
        'seenGuides': [...seenGuides]..sort(),
        if (savedSensorId != null) 'savedSensorId': savedSensorId,
        if (clockMode) 'clockMode': true,
        if (tiltGains != const TiltGains()) 'tiltGains': tiltGains.toJson(),
      };
}

/// One-time guides (Stance's `UserSettingsFlagsRepository.hasSeen…`).
enum Guide {
  feedbackWalkthrough,
  repEditGuide,
  preRecordingGuide,
  readinessTip,
  comparisonTip,
  historicalAverageTip,
  topSetTip,
}

/// Loads and saves [Preferences] as JSON in the app documents directory.
class PreferencesStore extends ValueNotifier<Preferences> {
  PreferencesStore({Future<Directory> Function()? baseDirectory})
      : _base = baseDirectory ?? getApplicationDocumentsDirectory,
        super(const Preferences());

  final Future<Directory> Function() _base;

  Future<File> _file() async => File('${(await _base()).path}/preferences.json');

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        value = Preferences.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Reading preferences failed: $e');
    }
  }

  bool hasSeen(Guide g) => value.seenGuides.contains(g.name);

  Future<void> markSeen(Guide g) async {
    if (hasSeen(g)) return;
    await update(value.copyWith(seenGuides: {...value.seenGuides, g.name}));
  }

  Future<void> update(Preferences p) async {
    value = p;
    try {
      await (await _file()).writeAsString(jsonEncode(p.toJson()));
    } catch (e) {
      debugPrint('Saving preferences failed: $e');
    }
  }
}
