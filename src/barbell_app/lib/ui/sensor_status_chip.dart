import 'package:flutter/material.dart';

import '../sensor/sensor_link.dart';
import '../workout/sensor_controller.dart';

/// Compact sensor state (name, connection, battery). Tap to open the
/// device page via [onPressed].
class SensorStatusChip extends StatelessWidget {
  const SensorStatusChip({super.key, required this.sensor, this.onPressed});

  final SensorController sensor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sensor,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final (icon, label, color) = switch (sensor.state) {
          _ when sensor.reconnecting =>
            (Icons.sync, 'Reconnecting…', scheme.tertiary),
          LinkState.streaming =>
            (Icons.sensors, sensor.link?.name ?? 'Sensor', scheme.primary),
          LinkState.connecting =>
            (Icons.bluetooth_searching, 'Connecting…', scheme.tertiary),
          LinkState.failed =>
            (Icons.error_outline, 'Sensor failed', scheme.error),
          LinkState.disconnected =>
            (Icons.sensors_off, 'No sensor', scheme.onSurfaceVariant),
        };
        final battery = sensor.batteryPercent;
        return ActionChip(
          avatar: Icon(icon, size: 18, color: color),
          label: Text(battery != null && sensor.isStreaming
              ? '$label · ${battery.toStringAsFixed(0)} %'
              : label),
          onPressed: onPressed,
        );
      },
    );
  }
}
