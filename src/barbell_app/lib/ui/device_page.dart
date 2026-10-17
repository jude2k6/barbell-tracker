import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../sensor/sensor_link.dart';
import '../sensor/witmotion/witmotion_link.dart';
import '../workout/sensor_controller.dart';
import 'app_scope.dart';
import 'auto_reconnect.dart';
import 'permission_prompts.dart';
import 'calibration_dialog.dart';
import 'format.dart';
import 'live_trace.dart';
import 'recordings_page.dart';
import 'scan_list.dart';

/// Sensor management: scan and connect, link health, live trace,
/// calibration, and access to the raw recordings.
class DevicePage extends StatelessWidget {
  const DevicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final sensor = AppScope.of(context).sensor;
    return AutoReconnect(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Device'),
          actions: [
            IconButton(
              tooltip: 'Raw recordings',
              icon: const Icon(Icons.folder_open),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const RecordingsPage())),
            ),
          ],
        ),
        body: ListenableBuilder(
          listenable: sensor,
          builder: (context, _) {
            final hasLink =
                sensor.link != null &&
                (sensor.isStreaming ||
                    sensor.state == LinkState.connecting ||
                    sensor.reconnecting);
            if (!hasLink) {
              final permissions = AppScope.of(context).permissions;
              return Column(
                children: [
                  if (permissions != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: BluetoothAccessBanner(service: permissions),
                    ),
                  if (sensor.state == LinkState.failed ||
                      sensor.lastError != null)
                    ListTile(
                      leading: Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: const Text('Connection failed'),
                      subtitle: Text('${sensor.lastError ?? 'Unknown error'}'),
                    ),
                  Expanded(
                    child: ScanList(
                      onSelected: (d) => _connect(context, sensor, d),
                    ),
                  ),
                  const _ForgetSavedTile(),
                ],
              );
            }
            return _ConnectedView(sensor: sensor);
          },
        ),
      ),
    );
  }

  Future<void> _connect(
    BuildContext context,
    SensorController sensor,
    BluetoothDevice device,
  ) async {
    await sensor.connect(WitMotionLink(device));
    if (!context.mounted) return;
    if (!sensor.isStreaming && sensor.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connect failed: ${sensor.lastError}')),
      );
    }
  }
}

class _ConnectedView extends StatefulWidget {
  const _ConnectedView({required this.sensor});

  final SensorController sensor;

  @override
  State<_ConnectedView> createState() => _ConnectedViewState();
}

class _ConnectedViewState extends State<_ConnectedView> {
  Timer? _stats;

  @override
  void initState() {
    super.initState();
    // Rate and loss figures refresh a few times a second.
    _stats = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stats?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sensor = widget.sensor;
    final rate = sensor.rate;
    final battery = sensor.batteryPercent;
    final streaming = sensor.isStreaming;
    final numbers = theme.textTheme.titleLarge.tabular;

    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          Text(value, style: numbers),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: Icon(streaming ? Icons.sensors : Icons.sync),
            title: Text(sensor.link?.name ?? 'Sensor'),
            subtitle: Text(
              sensor.reconnecting
                  ? 'Reconnecting…'
                  : switch (sensor.state) {
                      LinkState.streaming => 'Streaming',
                      LinkState.connecting => 'Connecting…',
                      LinkState.failed => 'Failed',
                      LinkState.disconnected => 'Disconnected',
                    },
            ),
            trailing: TextButton(
              onPressed: sensor.disconnect,
              child: const Text('Disconnect'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            stat(
              'Battery',
              battery == null ? '–' : '${battery.toStringAsFixed(0)} %',
            ),
            stat('Rate', '${rate.hz.toStringAsFixed(0)} Hz'),
            stat('Loss', '${(100 * rate.lossFraction).toStringAsFixed(1)} %'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'received ${rate.received} · missing ~${rate.estimatedMissing}'
          ' · clock jumps ${rate.clockJumps}',
          style: theme.textTheme.bodySmall.tabular,
        ),
        const SizedBox(height: 24),
        Text(
          'Vertical acceleration (g, gravity removed)',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        LiveTrace(sensor: sensor, height: 180),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.straighten),
          label: const Text('Calibrate (lay flat)'),
          onPressed: streaming
              ? () => CalibrationDialog.show(context, sensor.calibrateFlat)
              : null,
        ),
        const _ForgetSavedTile(),
      ],
    );
  }
}

/// "Forget saved device": disconnects and removes the remembered sensor so a
/// different one can be paired (Stance's `device_forget_saved` strings).
/// Hidden while nothing is saved.
class _ForgetSavedTile extends StatelessWidget {
  const _ForgetSavedTile();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final saved = app.savedSensor;
    final preferences = app.preferences;
    if (saved == null || preferences == null) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: preferences,
      builder: (context, _, _) => saved.hasSaved
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton(
                    key: const Key('forgetSavedSensor'),
                    onPressed: saved.forget,
                    child: const Text('Forget saved device'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Disconnects and removes the last device from saved preferences '
                    'so you can pair a different one.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
