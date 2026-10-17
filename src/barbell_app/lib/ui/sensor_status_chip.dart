import 'package:flutter/material.dart';

import '../sensor/sensor_link.dart';
import '../workout/sensor_controller.dart';
import 'stance_theme.dart';

/// Stance's `SmallDeviceStatusButton`: a pill with a sensor glyph and a
/// green (streaming) or red dot. Tap to open the device page via
/// [onPressed]. The state text (name, battery) is in the tooltip.
class SensorStatusChip extends StatelessWidget {
  const SensorStatusChip({super.key, required this.sensor, this.onPressed});

  final SensorController sensor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sensor,
      builder: (context, _) {
        final label = switch (sensor.state) {
          _ when sensor.reconnecting => 'Reconnecting…',
          LinkState.streaming => sensor.link?.name ?? 'Sensor',
          LinkState.connecting => 'Connecting…',
          LinkState.failed => 'Sensor failed',
          LinkState.disconnected => 'No sensor',
        };
        final battery = sensor.batteryPercent;
        final text = battery != null && sensor.isStreaming
            ? '$label · ${battery.toStringAsFixed(0)} %'
            : label;
        return Tooltip(
          message: text,
          child: Semantics(
            button: true,
            label: text,
            child: Material(
              color: const Color(0x0FFFFFFF),
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 10,
                      height: 20,
                      decoration: BoxDecoration(
                        color: const Color(0x1AFFFFFF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: sensor.isStreaming
                            ? StanceColors.connected
                            : StanceColors.disconnected,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
