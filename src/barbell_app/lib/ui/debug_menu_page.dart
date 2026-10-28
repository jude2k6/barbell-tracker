import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../workout/file_log.dart';
import 'app_scope.dart';
import 'app_theme.dart';
import 'app_widgets.dart';
import 'calibration_page.dart';
import 'device_stream_page.dart';
import 'sensor_status_chip.dart';
import 'workout_flow.dart';

/// Stance's `SettingsScreen` (back button, 26 dp title, status chip, 16 dp
/// padding), titled "Debug Menu" and opened from the Home
/// menu. Keeps the rows that work without an account: file logging with
/// "Share debug log", the device stream test, Calibration and "Forget saved
/// BLE devices". Skipped: Firebase ID, BLE stack switch, the Recording
/// screen, sync diagnostics and Sign out.
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            const SizedBox(height: 12),
            Row(
              children: [
                CircleIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Go back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      'Debug Menu',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                SensorStatusChip(
                  sensor: app.sensor,
                  onPressed: () => openDevice(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('File logging', style: theme.textTheme.titleSmall),
            Text(
              'Logs are saved automatically (last 5 MB). Share to send for support.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.subtitleGray,
              ),
            ),
            const SizedBox(height: 16),
            if (logPath != null) ...[
              FilledButton(
                key: const Key('shareDebugLog'),
                onPressed: () async {
                  await AppLog.file?.flush();
                  await share(logPath);
                },
                child: const Text('Share debug log'),
              ),
              const SizedBox(height: 16),
            ],
            FilledButton(
              key: const Key('deviceStreamMenu'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeviceStreamPage()),
              ),
              child: const Text('Test device data stream'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('calibrationMenu'),
              onPressed: () => openCalibration(context),
              child: const Text('Calibration'),
            ),
            if (saved != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('forgetSavedBle'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                ),
                onPressed: saved.forget,
                child: const Text('Forget saved BLE devices'),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// Sends the log file to the share sheet as plain text.
Future<void> shareDebugLog(String path) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path, mimeType: 'text/plain')],
      title: 'Share debug log',
    ),
  );
}
