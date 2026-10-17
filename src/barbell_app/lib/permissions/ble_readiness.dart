import 'package:flutter/foundation.dart';

/// Whether Bluetooth scanning can work right now (Stance's `BleReadiness`
/// and `BleReadinessRules`).
@immutable
class BleReadiness {
  const BleReadiness({required this.missingPermissions, required this.locationServicesOff});

  /// Android 12+ Bluetooth permissions, or location permission before that.
  final bool missingPermissions;

  /// Android 11 and older only find BLE devices while Location Services is on.
  final bool locationServicesOff;

  bool get isReady => !missingPermissions && !locationServicesOff;

  @override
  bool operator ==(Object other) =>
      other is BleReadiness &&
      other.missingPermissions == missingPermissions &&
      other.locationServicesOff == locationServicesOff;

  @override
  int get hashCode => Object.hash(missingPermissions, locationServicesOff);

  /// Last Android SDK (30 = Android 11) where scanning needs Location Services.
  static const maxSdkNeedingLocation = 30;

  /// [sdkInt] is the Android SDK level, or null on other platforms.
  static BleReadiness evaluate({
    required bool allPermissionsGranted,
    required bool locationServicesEnabled,
    required int? sdkInt,
  }) =>
      BleReadiness(
        missingPermissions: !allPermissionsGranted,
        locationServicesOff:
            sdkInt != null && sdkInt <= maxSdkNeedingLocation && !locationServicesEnabled,
      );
}
