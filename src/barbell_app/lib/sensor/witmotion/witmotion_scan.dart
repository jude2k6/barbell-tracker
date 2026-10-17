import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../sensor_link.dart';
import 'witmotion_link.dart';

/// Scans for the WitMotion sensor at [id] (a BLE remote id) and returns a
/// link to it, or null if it is not seen within [timeout]. Stops the scan
/// when done, like Stance's auto-reconnect.
Future<SensorLink?> findWitMotion(String id, Duration timeout) async {
  final wanted = id.toLowerCase();
  final found = Completer<BluetoothDevice>();
  final sub = FlutterBluePlus.onScanResults.listen((results) {
    for (final r in results) {
      if (r.device.remoteId.str.toLowerCase() == wanted && !found.isCompleted) {
        found.complete(r.device);
      }
    }
  });
  try {
    await FlutterBluePlus.startScan(timeout: timeout);
    final device = await found.future.timeout(timeout);
    return WitMotionLink(device);
  } on TimeoutException {
    return null;
  } finally {
    await sub.cancel();
    await FlutterBluePlus.stopScan();
  }
}
