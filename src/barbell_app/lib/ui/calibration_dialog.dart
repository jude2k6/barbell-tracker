import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'app_widgets.dart';
import 'format.dart';

enum _Phase { instructions, countdown, calibrating, done, failed }

/// Flat calibration, styled as Stance's `StanceAlertDialog` (Stance runs it
/// as `CalibrationScreen`): instructions, a countdown while the sensor settles,
/// then [onCalibrate], then a success (or failure) message.
class CalibrationDialog extends StatefulWidget {
  const CalibrationDialog({
    super.key,
    required this.onCalibrate,
    this.countdown = 5,
  });

  final Future<void> Function() onCalibrate;

  /// Seconds to wait with the sensor lying still before calibrating.
  final int countdown;

  static Future<void> show(
    BuildContext context,
    Future<void> Function() onCalibrate,
  ) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: AppAlert.scrim,
    builder: (_) => CalibrationDialog(onCalibrate: onCalibrate),
  );

  @override
  State<CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<CalibrationDialog> {
  _Phase _phase = _Phase.instructions;
  late int _remaining = widget.countdown;
  Timer? _timer;
  Object? _error;

  void _start() {
    setState(() {
      _phase = _Phase.countdown;
      _remaining = widget.countdown;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining > 1) {
        setState(() => _remaining--);
      } else {
        t.cancel();
        _calibrate();
      }
    });
  }

  Future<void> _calibrate() async {
    setState(() => _phase = _Phase.calibrating);
    try {
      await widget.onCalibrate();
      if (mounted) setState(() => _phase = _Phase.done);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _phase = _Phase.failed;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final busy = _phase == _Phase.countdown || _phase == _Phase.calibrating;
    void close() => Navigator.pop(context);
    final alert = switch (_phase) {
      _Phase.instructions => AppAlert(
        title: 'Calibration',
        message:
            'Place the WitMotion IMU on a flat, level surface and keep '
            'it still. Calibration runs for ${widget.countdown} seconds '
            'after you start.\n\nWhen you are ready, tap Start calibration.',
        actionText: 'Start calibration',
        onAction: _start,
        dismissText: 'Cancel',
        onDismiss: close,
      ),
      _Phase.countdown => AppAlert(
        title: 'Calibration',
        content: Column(
          children: [
            Text(
              'Lay flat, keep still',
              style: text.bodyMedium?.copyWith(
                color: AppColors.subtitleGray,
              ),
            ),
            const SizedBox(height: 8),
            Text('$_remaining s', style: text.headlineLarge.tabular),
          ],
        ),
      ),
      _Phase.calibrating => AppAlert(
        title: 'Calibration',
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text('Calibrating…', style: text.bodyMedium),
          ],
        ),
      ),
      _Phase.done => AppAlert(
        title: 'Calibration complete',
        message: 'IMU calibration finished successfully.',
        actionText: 'OK',
        onAction: close,
        onClose: close,
      ),
      _Phase.failed => AppAlert(
        title: 'Calibration failed',
        message: '$_error',
        actionText: 'OK',
        onAction: close,
        onClose: close,
      ),
    };
    return PopScope(canPop: !busy, child: alert);
  }
}
