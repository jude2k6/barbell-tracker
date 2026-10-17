import 'dart:async';

import 'package:flutter/material.dart';

enum _Phase { instructions, countdown, calibrating, done, failed }

/// Flat calibration: instructions, a countdown while the sensor settles,
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
          BuildContext context, Future<void> Function() onCalibrate) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
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
    final theme = Theme.of(context);
    final busy = _phase == _Phase.countdown || _phase == _Phase.calibrating;
    final Widget body = switch (_phase) {
      _Phase.instructions => const Text(
          'Lay the sensor flat on a level surface and keep it completely '
          'still until calibration finishes.'),
      _Phase.countdown => Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Lay flat, keep still',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          Text('$_remaining',
              style: theme.textTheme.displayLarge
                  ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      _Phase.calibrating => const Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Calibrating…'),
        ]),
      _Phase.done => Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          const Text('Calibration complete.'),
        ]),
      _Phase.failed => Text('Calibration failed: $_error'),
    };
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('Calibrate sensor'),
        content: body,
        actions: [
          if (_phase == _Phase.instructions) ...[
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(onPressed: _start, child: const Text('Start')),
          ],
          if (_phase == _Phase.done || _phase == _Phase.failed)
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done')),
        ],
      ),
    );
  }
}
