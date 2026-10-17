import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../workout/file_log.dart';
import 'app_scope.dart';
import 'device_stream_page.dart';
import 'sensor_status_chip.dart';
import 'workout_flow.dart';

/// Stance's Settings screen, titled "Debug Menu" and opened from the Home
/// menu. Keeps the rows that work without an account: file logging with
/// "Share debug log", the device stream test and "Forget saved BLE devices".
/// Skipped: Firebase ID, BLE stack switch, Recording and Calibration screens,
/// sync diagnostics and Sign out.
class DebugMenuPage extends StatelessWidget {
  const DebugMenuPage({super.key, this.share = shareDebugLog});

  /// Hands the log file to the system share sheet.
  final Future<void> Function(String path) share;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final logPath = AppLog.file?.sharablePath;
    final saved = app.savedSensor;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Menu'),
        actions: [
          SensorStatusChip(
            sensor: app.sensor,
            onPressed: () => openDevice(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('File logging', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Logs are saved automatically (last 5 MB). Share to send for support.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (logPath != null) ...[
            FilledButton(
              key: const Key('shareDebugLog'),
              onPressed: () async {
                await AppLog.file?.flush();
                await share(logPath);
              },
              child: const Text('Share debug log'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            key: const Key('deviceStreamMenu'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeviceStreamPage()),
            ),
            child: const Text('Test device data stream'),
          ),
          if (saved != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('forgetSavedBle'),
              onPressed: saved.forget,
              child: const Text('Forget saved BLE devices'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sends the log file to the share sheet as plain text.
Future<void> shareDebugLog(String path) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile(path, mimeType: 'text/plain')],
    title: 'Share debug log',
  ));
}
