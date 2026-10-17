import 'package:flutter/material.dart';

import '../analysis/exercises.dart';
import 'app_scope.dart';
import 'app_theme.dart';
import 'app_widgets.dart';
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

/// Stance's Home: the root lists the exercise groups; tapping one shows
/// its exercises (title becomes the group's, with a back button), and an
/// exercise opens its sessions. Settings menu and device status sit in
/// the top row.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ExerciseFamily? _group;

  void _openGroup(ExerciseFamily? group) => setState(() => _group = group);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final group = _group;
    return AutoReconnect(
      child: PopScope(
        canPop: group == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _openGroup(null);
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(children: [
                      if (group == null) ...[
                        _settingsMenu(context, app),
                        const Spacer(),
                        SensorStatusChip(
                          sensor: app.sensor,
                          onPressed: () => openDevice(context),
                        ),
                      ] else
                        CircleIconButton(
                          key: const Key('homeBack'),
                          icon: Icons.arrow_back,
                          tooltip: 'Back',
                          onPressed: () => _openGroup(null),
                        ),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group == null ? 'Exercise' : familyTitle(group),
                          style: theme.textTheme.headlineLarge),
                      const SizedBox(height: 8),
                      Text(
                        'Select an exercise to start a workout.',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: AppColors.subtitleGray),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
                    children: [
                      if (app.permissions != null)
                        BluetoothAccessBanner(service: app.permissions!),
                      if (group == null) const RecordingImportCard(),
                      ...exerciseListChildren(
                        context,
                        group: group,
                        onGroup: _openGroup,
                        onExercise: (e) => openSessions(context, e),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsMenu(BuildContext context, AppScope app) {
    PopupMenuItem<VoidCallback> item(
            IconData icon, String text, VoidCallback open, {Key? key}) =>
        PopupMenuItem(
          key: key,
          value: open,
          child: Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(text),
          ]),
        );
    void push(Widget page) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page));
    return PopupMenuButton<VoidCallback>(
      key: const Key('homeMenu'),
      tooltip: 'Settings menu',
      onSelected: (open) => open(),
      itemBuilder: (context) => [
        item(Icons.tune, 'Preferences', () => push(const PreferencesPage())),
        if (app.preferences case final prefs?)
          item(Icons.person, 'User Details',
              () => showUserDetailsSheet(context, prefs),
              key: const Key('userDetailsMenu')),
        item(Icons.folder_open, 'Recordings', () => push(const RecordingsPage())),
        item(Icons.build, 'Debug Menu', () => push(const DebugMenuPage()),
            key: const Key('debugMenu')),
      ],
      child: const CircleIconButton(icon: Icons.settings),
    );
  }
}
