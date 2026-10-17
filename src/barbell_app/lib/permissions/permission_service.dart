/// App-wide permission and Bluetooth-radio state.
///
/// Every feature that needs Bluetooth, the camera or the microphone goes
/// through [PermissionService] instead of letting each plugin prompt on
/// first use. Status is re-checked when the app returns to the foreground,
/// so changes made in system Settings are picked up.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_readiness.dart';
enum AppCapability {
  bluetooth('Bluetooth', 'connect to your barbell sensor'),
  camera('Camera', 'record your sets on video'),
  microphone('Microphone', 'record sound with set videos');

  const AppCapability(this.label, this.purpose);
  final String label;

  /// Completes "…is needed to [purpose]."
  final String purpose;
}

enum Access {
  /// Not asked yet, or denied but the system will prompt again.
  askable,
  granted,

  /// Denied with "don't ask again" (Android) or denied once (iOS):
  /// only system Settings can change it.
  blocked,

  /// Disallowed by parental controls / device policy.
  restricted,
}

/// State of the Bluetooth radio, separate from the permission.
enum RadioState { on, off, unavailable, unknown }

/// Thin wrapper over the plugins so the service can be tested.
abstract class PermissionBackend {
  Future<Access> status(AppCapability c);
  Future<Access> request(AppCapability c);
  Future<bool> openSettings();
  Stream<RadioState> get radio;

  /// Ask the OS to switch Bluetooth on. Android only; false elsewhere.
  Future<bool> turnOnBluetooth();

  /// Android SDK level (30 = Android 11); null on other platforms.
  Future<int?> androidSdk();

  /// Whether the device's Location Services switch is on.
  Future<bool> locationServicesEnabled();

  /// Open the system Location settings. Android only.
  Future<bool> openLocationSettings();
}

class PluginPermissionBackend implements PermissionBackend {
  int? _sdk;

  @override
  Future<int?> androidSdk() async {
    if (!Platform.isAndroid) return null;
    return _sdk ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  }

  Future<List<Permission>> _permissions(AppCapability c) async => switch (c) {
        // Android 12+: scan + connect. On Android ≤ 11 those report granted
        // and scanning needs location permission instead.
        AppCapability.bluetooth when Platform.isAndroid =>
          (await androidSdk())! <= BleReadiness.maxSdkNeedingLocation
              ? [Permission.locationWhenInUse]
              : [Permission.bluetoothScan, Permission.bluetoothConnect],
        AppCapability.bluetooth => [Permission.bluetooth],
        AppCapability.camera => [Permission.camera],
        AppCapability.microphone => [Permission.microphone],
      };

  static Access _combine(Iterable<PermissionStatus> s) {
    if (s.every((x) => x.isGranted || x.isLimited)) return Access.granted;
    if (s.any((x) => x.isRestricted)) return Access.restricted;
    if (s.any((x) => x.isPermanentlyDenied)) return Access.blocked;
    return Access.askable;
  }

  @override
  Future<Access> status(AppCapability c) async =>
      _combine(await Future.wait((await _permissions(c)).map((p) => p.status)));

  @override
  Future<Access> request(AppCapability c) async {
    final result = await (await _permissions(c)).request();
    return _combine(result.values);
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  @override
  Stream<RadioState> get radio => FlutterBluePlus.adapterState.map((s) => switch (s) {
        BluetoothAdapterState.on => RadioState.on,
        BluetoothAdapterState.off ||
        BluetoothAdapterState.turningOff ||
        BluetoothAdapterState.turningOn =>
          RadioState.off,
        BluetoothAdapterState.unavailable => RadioState.unavailable,
        // "unauthorized" is the permission, tracked separately.
        _ => RadioState.unknown,
      });

  @override
  Future<bool> locationServicesEnabled() async =>
      (await Permission.locationWhenInUse.serviceStatus) == ServiceStatus.enabled;

  @override
  Future<bool> openLocationSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      await const AndroidIntent(action: 'android.settings.LOCATION_SOURCE_SETTINGS').launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> turnOnBluetooth() async {
    if (!Platform.isAndroid) return false;
    try {
      await FlutterBluePlus.turnOn();
      return true;
    } catch (_) {
      return false;
    }
  }
}

class PermissionService extends ChangeNotifier with WidgetsBindingObserver {
  PermissionService({PermissionBackend? backend, bool observeLifecycle = true})
      : _backend = backend ?? PluginPermissionBackend() {
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    _observing = observeLifecycle;
    _radioSub = _backend.radio.listen((r) {
      _radio = r;
      notifyListeners();
    }, onError: (Object _) {});
    refresh();
  }

  final PermissionBackend _backend;
  late final StreamSubscription<RadioState> _radioSub;
  late final bool _observing;

  final _access = <AppCapability, Access>{};
  RadioState _radio = RadioState.unknown;
  bool _locationServicesOff = false;

  /// Last known status; [Access.askable] until the first check completes.
  Access access(AppCapability c) => _access[c] ?? Access.askable;
  bool granted(AppCapability c) => access(c) == Access.granted;

  RadioState get radio => _radio;

  /// Bluetooth permission granted and the radio not known to be off.
  bool get bluetoothReady =>
      granted(AppCapability.bluetooth) && _radio != RadioState.off && _radio != RadioState.unavailable;

  /// Bluetooth permission and, on Android 11 and older, Location Services
  /// (Stance's `BleReadinessRules`). Location Services aren't a permission,
  /// so they're checked here and not through [AppCapability].
  BleReadiness get readiness => BleReadiness(
        missingPermissions: !granted(AppCapability.bluetooth),
        locationServicesOff: _locationServicesOff,
      );

  /// [bluetoothReady] and no Location Services problem: a scan can work.
  bool get scanReady => bluetoothReady && !_locationServicesOff;

  Future<void> refresh() async {
    for (final c in AppCapability.values) {
      try {
        _access[c] = await _backend.status(c);
      } catch (_) {
        // Plugin unavailable (tests, unsupported platform): leave as is.
      }
    }
    try {
      _locationServicesOff = BleReadiness.evaluate(
        allPermissionsGranted: true,
        locationServicesEnabled: await _backend.locationServicesEnabled(),
        sdkInt: await _backend.androidSdk(),
      ).locationServicesOff;
    } catch (_) {
      _locationServicesOff = false;
    }
    notifyListeners();
  }

  /// Ask the OS for [c] if it can still prompt. Returns the new status.
  Future<Access> request(AppCapability c) async {
    final current = await _backend.status(c);
    final result = current == Access.askable ? await _backend.request(c) : current;
    _access[c] = result;
    notifyListeners();
    return result;
  }

  Future<bool> openSettings() => _backend.openSettings();

  Future<bool> turnOnBluetooth() => _backend.turnOnBluetooth();

  Future<bool> openLocationSettings() => _backend.openLocationSettings();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _radioSub.cancel();
    super.dispose();
  }
}
