import 'sensor_sample.dart';

enum LinkState { disconnected, connecting, streaming, failed }

/// A connected barbell sensor. WitMotion is the first implementation; the
/// DIY sensor will be a second one behind the same interface.
abstract class SensorLink {
  String get name;

  /// Stable address of the device (the BLE remote id), saved so the sensor
  /// can be found again after a restart.
  String get id;

  Stream<LinkState> get state;
  Stream<SensorSample> get samples;

  /// Battery percentage, null until the first reading arrives.
  Stream<double?> get batteryPercent;

  Future<void> connect();
  Future<void> disconnect();

  /// Zero the accelerometer while the sensor lies flat and still.
  Future<void> calibrateFlat();
}
