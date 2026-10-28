import 'dart:async';

import 'package:barbell_app/permissions/ble_readiness.dart';
import 'package:barbell_app/permissions/permission_service.dart';
import 'package:barbell_app/ui/permission_prompts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBackend implements PermissionBackend {
  FakeBackend({Map<AppCapability, Access>? status, this.grantOnRequest = true})
      : current = {for (final c in AppCapability.values) c: Access.askable, ...?status};

  final Map<AppCapability, Access> current;
  bool grantOnRequest;
  final requests = <AppCapability>[];
  int settingsOpened = 0;
  int turnOnCalls = 0;
  final radioCtl = StreamController<RadioState>.broadcast();

  @override
  Future<Access> status(AppCapability c) async => current[c]!;

  @override
  Future<Access> request(AppCapability c) async {
    requests.add(c);
    return current[c] = grantOnRequest ? Access.granted : Access.blocked;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Stream<RadioState> get radio => radioCtl.stream;

  @override
  Future<bool> turnOnBluetooth() async {
    turnOnCalls++;
    return false;
  }

  int? sdk;
  bool locationOn = true;
  int locationSettingsOpened = 0;

  @override
  Future<int?> androidSdk() async => sdk;

  @override
  Future<bool> locationServicesEnabled() async => locationOn;

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsOpened++;
    return true;
  }
}

PermissionService service(FakeBackend b) =>
    PermissionService(backend: b, observeLifecycle: false);

/// Pumps a button that runs [ensureAccess] and records the result.
Future<List<bool>> host(WidgetTester tester, PermissionService s, AppCapability c) async {
  final results = <bool>[];
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => results.add(await ensureAccess(context, s, c)),
          child: const Text('go'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  group('PermissionService', () {
    test('refresh reads every capability', () async {
      final b = FakeBackend(status: {AppCapability.camera: Access.granted});
      final s = service(b);
      await s.refresh();
      expect(s.granted(AppCapability.camera), isTrue);
      expect(s.access(AppCapability.bluetooth), Access.askable);
    });

    test('request only prompts when the OS still can', () async {
      final b = FakeBackend(status: {AppCapability.microphone: Access.blocked});
      final s = service(b);
      expect(await s.request(AppCapability.microphone), Access.blocked);
      expect(b.requests, isEmpty);
      expect(await s.request(AppCapability.camera), Access.granted);
      expect(b.requests, [AppCapability.camera]);
    });

    test('resume re-checks status (e.g. after visiting Settings)', () async {
      final b = FakeBackend(status: {AppCapability.camera: Access.blocked});
      final s = service(b);
      await s.refresh();
      b.current[AppCapability.camera] = Access.granted;
      s.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(s.granted(AppCapability.camera), isTrue);
    });

    test('bluetoothReady needs the permission and the radio not off', () async {
      final b = FakeBackend(status: {AppCapability.bluetooth: Access.granted});
      final s = service(b);
      await s.refresh();
      expect(s.bluetoothReady, isTrue); // radio unknown counts as ready
      b.radioCtl.add(RadioState.off);
      await Future<void>.delayed(Duration.zero);
      expect(s.bluetoothReady, isFalse);
      b.radioCtl.add(RadioState.on);
      await Future<void>.delayed(Duration.zero);
      expect(s.bluetoothReady, isTrue);
    });
  });

  group('ensureAccess', () {
    testWidgets('explains, then prompts, then succeeds', (tester) async {
      final b = FakeBackend();
      final s = service(b);
      final results = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                results.add(await ensureAccess(context, s, AppCapability.camera)),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Allow camera access'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(b.requests, [AppCapability.camera]);
      expect(results, [true]);
    });

    testWidgets('"Not now" skips the system prompt', (tester) async {
      final b = FakeBackend();
      final s = service(b);
      final results = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                results.add(await ensureAccess(context, s, AppCapability.camera)),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(b.requests, isEmpty);
      expect(results, [false]);
    });

    testWidgets('blocked offers Open settings', (tester) async {
      final b = FakeBackend(status: {AppCapability.microphone: Access.blocked});
      final s = service(b);
      final results = await host(tester, s, AppCapability.microphone);
      expect(find.text('Microphone access is off'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(b.settingsOpened, 1);
      expect(results, [false]);
    });

    testWidgets('granted returns immediately without dialogs', (tester) async {
      final b = FakeBackend(status: {AppCapability.camera: Access.granted});
      final s = service(b);
      final results = await host(tester, s, AppCapability.camera);
      expect(find.byType(AlertDialog), findsNothing);
      expect(results, [true]);
    });

    testWidgets('Bluetooth granted but radio off is reported', (tester) async {
      final b = FakeBackend(status: {AppCapability.bluetooth: Access.granted});
      final s = service(b);
      b.radioCtl.add(RadioState.off);
      await tester.pump();
      await host(tester, s, AppCapability.bluetooth);
      expect(find.text('Bluetooth is off'), findsOneWidget);
    });
  });

  group('BluetoothAccessBanner', () {
    testWidgets('hidden when ready, shown when access is missing', (tester) async {
      final b = FakeBackend(status: {AppCapability.bluetooth: Access.granted});
      final s = service(b);
      await s.refresh();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BluetoothAccessBanner(service: s))));
      expect(find.byKey(const Key('bluetoothBanner')), findsNothing);

      b.current[AppCapability.bluetooth] = Access.blocked;
      await s.refresh();
      await tester.pump();
      expect(find.text('Bluetooth access is off for this app.'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
    });
  });

  group('BleReadiness', () {
    test('location services only matter on Android 11 and older', () {
      BleReadiness at(int? sdk, {required bool on, bool granted = true}) => BleReadiness.evaluate(
          allPermissionsGranted: granted, locationServicesEnabled: on, sdkInt: sdk);
      expect(at(30, on: false).locationServicesOff, isTrue);
      expect(at(31, on: false).locationServicesOff, isFalse);
      expect(at(null, on: false).locationServicesOff, isFalse);
      expect(at(28, on: true).isReady, isTrue);
      expect(at(30, on: false).isReady, isFalse);
      expect(at(33, on: true, granted: false).missingPermissions, isTrue);
    });

    test('the service reads Location Services on refresh', () async {
      final b = FakeBackend(status: {AppCapability.bluetooth: Access.granted})
        ..sdk = 30
        ..locationOn = false;
      final s = service(b);
      await s.refresh();
      expect(s.readiness.locationServicesOff, isTrue);
      expect(s.scanReady, isFalse);
      expect(s.bluetoothReady, isTrue);
      b.locationOn = true;
      s.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(s.scanReady, isTrue);
    });
  });

  group('ensureLocationServices', () {
    Future<List<bool>> run(WidgetTester tester, PermissionService s, {bool anyway = false}) async {
      final results = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results
                .add(await ensureLocationServices(context, s, continueAnyway: anyway)),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return results;
    }

    FakeBackend off() => FakeBackend(status: {AppCapability.bluetooth: Access.granted})
      ..sdk = 29
      ..locationOn = false;

    testWidgets('silent when Location Services is on or not needed', (tester) async {
      final b = off()..sdk = 33;
      final results = await run(tester, service(b));
      expect(find.byType(AlertDialog), findsNothing);
      expect(results, [true]);
    });

    testWidgets('"Not now" declines', (tester) async {
      final results = await run(tester, service(off()));
      expect(find.text('Location is off'), findsOneWidget);
      expect(find.text('Turn on Location'), findsOneWidget);
      expect(find.text('Continue anyway'), findsNothing);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });

    testWidgets('"Continue anyway" proceeds', (tester) async {
      final results = await run(tester, service(off()), anyway: true);
      expect(find.text('Not now'), findsNothing);
      await tester.tap(find.text('Continue anyway'));
      await tester.pumpAndSettle();
      expect(results, [true]);
    });

    testWidgets('"Turn on Location" opens settings and closes once it is on', (tester) async {
      final b = off();
      final s = service(b);
      final results = await run(tester, s);
      await tester.tap(find.text('Turn on Location'));
      await tester.pumpAndSettle();
      expect(b.locationSettingsOpened, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      b.locationOn = true;
      await s.refresh();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(results, [true]);
    });
  });
}
