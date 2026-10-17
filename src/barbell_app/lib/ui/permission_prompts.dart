import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../permissions/permission_service.dart';
import 'stance_theme.dart';

/// Make sure [capability] is usable, explaining and prompting as needed.
///
/// - Not asked yet: a short explanation, then the system prompt.
/// - Blocked: an explanation with "Open settings".
/// - Restricted: an explanation only.
/// - Bluetooth: also checks the radio and offers to turn it on.
///
/// Returns true if the capability can be used now.
Future<bool> ensureAccess(
  BuildContext context,
  PermissionService service,
  AppCapability capability,
) async {
  var access = service.access(capability);
  if (access != Access.granted) {
    await service.refresh();
    access = service.access(capability);
  }
  if (!context.mounted) return false;

  if (access == Access.askable) {
    final go = await _dialog(
      context,
      title: 'Allow ${capability.label.toLowerCase()} access',
      body: '${capability.label} is needed to ${capability.purpose}. '
          'Your phone will ask you next.',
      action: 'Continue',
    );
    if (go != true) return false;
    access = await service.request(capability);
    if (!context.mounted) return false;
  }

  if (access == Access.blocked) {
    final open = await _dialog(
      context,
      title: '${capability.label} access is off',
      body: '${capability.label} is needed to ${capability.purpose}. '
          'Turn it on for Barbell Tracker in Settings, then come back.',
      action: 'Open settings',
    );
    if (open == true) await service.openSettings();
    return false;
  }
  if (access == Access.restricted) {
    await _dialog(
      context,
      title: '${capability.label} is restricted',
      body: 'This device does not allow ${capability.label.toLowerCase()} '
          'access for apps (for example through parental controls).',
    );
    return false;
  }
  if (access != Access.granted) return false;

  if (capability == AppCapability.bluetooth) {
    return ensureBluetoothOn(context, service);
  }
  return true;
}

/// Prompt to switch the radio on if it is off. Returns true when on or
/// unknown (scanning will then report its own error).
Future<bool> ensureBluetoothOn(BuildContext context, PermissionService service) async {
  switch (service.radio) {
    case RadioState.on || RadioState.unknown:
      return true;
    case RadioState.unavailable:
      await _dialog(context,
          title: 'Bluetooth unavailable',
          body: 'This device has no Bluetooth LE support.');
      return false;
    case RadioState.off:
      if (Platform.isAndroid) {
        final on = await _dialog(context,
            title: 'Bluetooth is off',
            body: 'Turn on Bluetooth to connect to your sensor.',
            action: 'Turn on');
        if (on != true) return false;
        return service.turnOnBluetooth();
      }
      await _dialog(context,
          title: 'Bluetooth is off',
          body: 'Turn on Bluetooth in Control Centre or Settings, then try again.');
      return false;
  }
}

/// Stance's "Location is off" prompt (`BleReadinessDialog`): on Android 11
/// and older, BLE scanning finds nothing while Location Services is off.
///
/// Returns true when scanning can work (or when [continueAnyway] is set and
/// the user chose "Continue anyway"), false after "Not now". With
/// [continueAnyway] the dismiss button reads "Continue anyway" instead of
/// "Not now", as on Stance's Sessions screen. "Turn on Location" opens the
/// system Location settings; the dialog closes by itself once Location
/// Services is on again.
///
/// Stance's version also covers missing permissions ("Grant permissions",
/// "Open settings"); here [ensureAccess] does that first.
Future<bool> ensureLocationServices(
  BuildContext context,
  PermissionService service, {
  bool continueAnyway = false,
}) async {
  await service.refresh();
  if (!service.readiness.locationServicesOff || !context.mounted) return true;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _LocationOffDialog(service: service, continueAnyway: continueAnyway),
  );
  return result ?? false;
}

class _LocationOffDialog extends StatelessWidget {
  const _LocationOffDialog({required this.service, required this.continueAnyway});

  final PermissionService service;
  final bool continueAnyway;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: service,
        builder: (context, _) {
          if (!service.readiness.locationServicesOff) {
            // Turned on in Settings: close and let the caller carry on.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.of(context).pop(true);
            });
          }
          return AlertDialog(
            key: const Key('locationOffDialog'),
            title: const Text('Location is off'),
            content: const Text('This Android version requires Location Services to be on '
                'for Bluetooth scanning. Turn it on to find your sensor.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, continueAnyway),
                child: Text(continueAnyway ? 'Continue anyway' : 'Not now'),
              ),
              FilledButton(
                onPressed: service.openLocationSettings,
                child: const Text('Turn on Location'),
              ),
            ],
          );
        },
      );
}

Future<bool?> _dialog(
  BuildContext context, {
  required String title,
  required String body,
  String? action,
}) =>
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(action == null ? 'OK' : 'Not now'),
          ),
          if (action != null)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
        ],
      ),
    );

/// Banner shown on Home and Device when Bluetooth can't be used yet.
class BluetoothAccessBanner extends StatelessWidget {
  const BluetoothAccessBanner({super.key, required this.service});

  final PermissionService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: service,
        builder: (context, _) {
          final access = service.access(AppCapability.bluetooth);
          final (String text, String? button) = switch ((access, service.radio)) {
            (Access.granted, RadioState.off) => ('Bluetooth is off.', Platform.isAndroid ? 'Turn on' : null),
            (Access.granted, RadioState.unavailable) => ('This device has no Bluetooth LE.', null),
            (Access.granted, _) => ('', null),
            (Access.blocked, _) => ('Bluetooth access is off for this app.', 'Open settings'),
            (Access.restricted, _) => ('Bluetooth is restricted on this device.', null),
            (Access.askable, _) => ('Allow Bluetooth to connect to your sensor.', 'Allow'),
          };
          if (text.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              key: const Key('bluetoothBanner'),
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(children: [
                  const Icon(Icons.bluetooth_disabled, color: StanceColors.error),
                  const SizedBox(width: 12),
                  Expanded(child: Text(text)),
                  if (button != null)
                    TextButton(
                      onPressed: () => ensureAccess(context, service, AppCapability.bluetooth),
                      child: Text(button),
                    ),
                ]),
              ),
            ),
          );
        },
      );
}
