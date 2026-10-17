import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'auto_reconnect.dart';
import 'debug_menu_page.dart';
import 'exercise_list.dart';
import 'permission_prompts.dart';
import 'preferences_page.dart';
import 'recording_import_card.dart';
import 'recordings_page.dart';
import 'sensor_status_chip.dart';
import 'user_details_sheet.dart';
import 'workout_flow.dart';

/// Stance's Home: pick an exercise to open its sessions. Device status and
/// the menu sit in the top bar.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    return AutoReconnect(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Exercise'),
          actions: [
            SensorStatusChip(
              sensor: app.sensor,
              onPressed: () => openDevice(context),
            ),
            PopupMenuButton<VoidCallback>(
              key: const Key('homeMenu'),
              onSelected: (open) => open(),
              itemBuilder: (context) => [
                if (app.preferences case final prefs?)
                  PopupMenuItem(
                    key: const Key('userDetailsMenu'),
                    value: () => showUserDetailsSheet(context, prefs),
                    child: const Text('User Details'),
                  ),
                PopupMenuItem(
                  value: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PreferencesPage()),
                  ),
                  child: const Text('Preferences'),
                ),
                PopupMenuItem(
                  value: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RecordingsPage()),
                  ),
                  child: const Text('Recordings'),
                ),
                PopupMenuItem(
                  key: const Key('debugMenu'),
                  value: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DebugMenuPage()),
                  ),
                  child: const Text('Debug Menu'),
                ),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            if (app.permissions != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: BluetoothAccessBanner(service: app.permissions!),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Select an exercise to start a workout.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const RecordingImportCard(),
            ...exerciseListChildren(context, (e) => openSessions(context, e)),
          ],
        ),
      ),
    );
  }
}
