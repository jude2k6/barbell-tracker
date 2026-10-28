import 'dart:async';

import 'package:flutter/material.dart';

import '../workout/file_log.dart';
import '../workout/sensor_controller.dart';
import 'app_scope.dart';
import 'app_widgets.dart';
import 'format.dart';
import 'sensor_status_chip.dart';
import 'workout_flow.dart';

/// Seconds the sensor must stay flat after the calibration command
/// (Stance's `CalibrationViewModel.startCalibration` loop of 10 × 1 s).
const calibrationSeconds = 10;

/// Opens the [CalibrationPage].
Future<void> openCalibration(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => const CalibrationPage()));

/// Stance's `CalibrationScreen` (route `calibration`, opened from the Debug
/// Menu): a top bar (back, "Calibration", device status), the
/// instructions, a status line and a full-width "Start calibration" button
/// at the bottom.
///
/// As in `CalibrationViewModel`, Start sends the WitMotion flat-surface
/// calibration (`FF AA 01 01 00`) at once, then counts 10 s down while
/// the sensor calibrates itself, then shows "Calibration complete". Start
/// needs a streaming sensor. Leaving the page mid-run is allowed; the
/// command has already been sent.
class CalibrationPage extends StatefulWidget {
  const CalibrationPage({super.key});

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  static const _tag = 'Calibration';

  /// Seconds left while calibrating; null when idle (Stance's
  /// `secondsRemaining`).
  int? _remaining;
  Timer? _timer;

  bool get _calibrating => _timer != null;

  void _start(SensorController sensor) {
    if (!sensor.isStreaming || _calibrating) return;
    AppLog.i(_tag, 'flat calibration started');
    setState(() => _remaining = calibrationSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _remaining! - 1;
      if (left > 0) {
        setState(() => _remaining = left);
      } else {
        _finish();
      }
    });
    // Stance fires the write and never hears back; ours reports a failed
    // BLE write instead of counting down to a false "complete".
    sensor.calibrateFlat().catchError((Object e) {
      AppLog.w(_tag, 'flat calibration write failed', e);
      if (!mounted || !_calibrating) return;
      _stop();
      _showResult(
        title: 'Calibration failed',
        message: '$e',
      );
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    setState(() => _remaining = null);
  }

  void _finish() {
    _stop();
    AppLog.i(_tag, 'flat calibration finished');
    _showResult(
      title: 'Calibration complete',
      message: 'IMU calibration finished successfully.',
    );
  }

  /// Stance's `StanceAlertDialog`: X and OK both only dismiss it, leaving
  /// the page open.
  void _showResult({required String title, required String message}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sensor = AppScope.of(context).sensor;
    final text = Theme.of(context).textTheme;
    final hint = text.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      // Material 3 TopAppBar on the background colour.
      appBar: AppBar(
        leading: IconButton(
          key: const Key('calibrationBack'),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Calibration'),
        foregroundColor: Colors.white,
        actions: [
          SensorStatusChip(
            sensor: sensor,
            onPressed: () => openDevice(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListenableBuilder(
        listenable: sensor,
        builder: (context, _) {
          final connected = sensor.isStreaming;
          final canStart = connected && !_calibrating;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                Text(
                  'Place the WitMotion IMU on a flat, level surface and keep '
                  'it still. Calibration runs for $calibrationSeconds seconds '
                  'after you start.',
                  textAlign: TextAlign.start,
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 8),
                if (!connected)
                  Text(
                    'Connect a WitMotion IMU from the Devices screen to '
                    'calibrate.',
                    style: hint,
                  )
                else if (_remaining != null)
                  Text(
                    '$_remaining s',
                    key: const Key('calibrationCountdown'),
                    style: text.displaySmall.tabular,
                  )
                else
                  Text('When you are ready, tap Start calibration.',
                      style: hint),
                const Spacer(),
                AppButton(
                  key: const Key('calibrationStart'),
                  text: _calibrating ? 'Calibrating…' : 'Start calibration',
                  style: canStart
                      ? AppButtonStyle.primary
                      : AppButtonStyle.idle,
                  height: 48,
                  onPressed: canStart ? () => _start(sensor) : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
