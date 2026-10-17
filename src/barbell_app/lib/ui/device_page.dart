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
import 'stance_theme.dart';
import 'stance_widgets.dart';

/// Sensor management, laid out like Stance's `DeviceScreen`: top bar (back,
/// refresh), "Devices" header, then the scan list or, once linked, link
/// health, live trace, calibration and access to the raw recordings.
class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  /// Bumped by the refresh button; [ScanList] rescans on every change.
  final _rescan = ValueNotifier(0);

  @override
  void dispose() {
    _rescan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sensor = AppScope.of(context).sensor;
    final text = Theme.of(context).textTheme;
    return AutoReconnect(
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              // DeviceManagementTopBar.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  spacing: 8,
                  children: [
                    CircleIconButton(
                      key: const Key('deviceBack'),
                      icon: Icons.arrow_back,
                      tooltip: 'Go back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    CircleIconButton(
                      key: const Key('deviceRefresh'),
                      icon: Icons.refresh,
                      tooltip: 'Refresh devices',
                      onPressed: () => _rescan.value++,
                    ),
                    const Spacer(),
                    CircleIconButton(
                      icon: Icons.folder_open,
                      tooltip: 'Raw recordings',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RecordingsPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // DeviceScreenHeader.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Devices', style: text.headlineLarge),
                    Text(
                      'Select a device to connect to.',
                      style: text.bodyLarge?.copyWith(
                        color: StanceColors.subtitleGray,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(child: _body(context, sensor)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, SensorController sensor) {
    return ListenableBuilder(
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: BluetoothAccessBanner(service: permissions),
                ),
              if (sensor.state == LinkState.failed || sensor.lastError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: DevicePanel(
                    child: Row(
                      spacing: 12,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: StanceColors.error,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Connection failed',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              Text(
                                '${sensor.lastError ?? 'Unknown error'}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: StanceColors.subtitleGray,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: ScanList(
                  rescan: _rescan,
                  onSelected: (d) => _connect(context, sensor, d),
                ),
              ),
              const _ForgetSavedTile(),
            ],
          );
        }
        return _ConnectedView(sensor: sensor);
      },
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
    final statusText = sensor.reconnecting
        ? 'Reconnecting…'
        : switch (sensor.state) {
            LinkState.streaming => 'Streaming',
            LinkState.connecting => 'Connecting…',
            LinkState.failed => 'Failed',
            LinkState.disconnected => 'Disconnected',
          };

    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: StanceColors.subtitleGray,
            ),
          ),
          Text(value, style: numbers),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        // StanceTrackerDeviceRow, connected: dot, name, battery.
        DevicePanel(
          minHeight: 52,
          child: Row(
            children: [
              Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: streaming
                      ? StanceColors.connected
                      : StanceColors.subtitleGray,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sensor.link?.name ?? 'Sensor',
                        style: theme.textTheme.bodyLarge,
                      ),
                      Text(
                        statusText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: StanceColors.subtitleGray,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (battery != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '🔋 ${battery.clamp(0, 100).toInt()}%',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: StanceColors.connected,
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              DevicePill(
                text: 'Disconnect',
                fill: const Color(0x1AFFFFFF),
                onTap: sensor.disconnect,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        DevicePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  stat(
                    'Battery',
                    battery == null ? '–' : '${battery.toStringAsFixed(0)} %',
                  ),
                  stat('Rate', '${rate.hz.toStringAsFixed(0)} Hz'),
                  stat(
                    'Loss',
                    '${(100 * rate.lossFraction).toStringAsFixed(1)} %',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'received ${rate.received} · missing ~${rate.estimatedMissing}'
                ' · clock jumps ${rate.clockJumps}',
                style: theme.textTheme.bodySmall.tabular?.copyWith(
                  color: StanceColors.subtitleGray,
                ),
              ),
            ],
          ),
        ),
        // DeviceSectionHeader.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Vertical acceleration (g, gravity removed)',
            style: theme.textTheme.titleSmall?.copyWith(
              color: StanceColors.subtitleGray,
            ),
          ),
        ),
        DevicePanel(child: LiveTrace(sensor: sensor, height: 180)),
        const SizedBox(height: 16),
        StanceButton(
          text: 'Calibrate (lay flat)',
          height: 48,
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
                  StanceButton(
                    key: const Key('forgetSavedSensor'),
                    text: 'Forget saved device',
                    style: StanceButtonStyle.secondary,
                    onPressed: saved.forget,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Disconnects and removes the last device from saved preferences '
                    'so you can pair a different one.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: StanceColors.subtitleGray),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
