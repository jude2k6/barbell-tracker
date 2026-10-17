import 'package:flutter/material.dart';

import '../workout/preferences.dart';
import '../workout/session.dart';
import '../workout/user_profile.dart';
import 'app_scope.dart';

/// Stance's Preferences: weight unit (used for weight input) and height
/// unit. Like Stance, changes apply on Done; going back discards them.
class PreferencesPage extends StatefulWidget {
  const PreferencesPage({super.key});

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  PreferencesStore? _store;
  late WeightUnit _weight;
  late HeightUnit _height;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = AppScope.of(context).preferences;
    if (store == null || identical(store, _store)) return;
    _store = store;
    _weight = store.value.weightUnit;
    _height = store.value.heightUnit;
  }

  /// Like Stance, saves in the background and leaves at once.
  void _done() {
    final store = _store;
    if (store != null) {
      final p = store.value;
      if (p.weightUnit != _weight || p.heightUnit != _height) {
        store.update(p.copyWith(weightUnit: _weight, heightUnit: _height));
      }
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget unitRow<T>(
      Key key,
      List<(T, String)> options,
      T selected,
      ValueChanged<T> onSelected,
    ) => SegmentedButton<T>(
      key: key,
      segments: [
        for (final (v, label) in options)
          ButtonSegment(value: v, label: Text(label)),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => onSelected(s.first)),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferences'),
        actions: [
          TextButton(
            key: const Key('preferencesDone'),
            onPressed: _done,
            child: const Text('Done'),
          ),
        ],
      ),
      body: _store == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Customize your app experience',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text('Weight Unit', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                unitRow(
                  const Key('weightUnitPreference'),
                  const [(WeightUnit.kg, 'kg'), (WeightUnit.lb, 'lb')],
                  _weight,
                  (u) => _weight = u,
                ),
                const SizedBox(height: 8),
                Text(
                  'This preference will be used for exercise weight input.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                Text('Height Unit', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                unitRow(
                  const Key('heightUnitPreference'),
                  const [(HeightUnit.cm, 'cm'), (HeightUnit.ftIn, 'ft-in')],
                  _height,
                  (u) => _height = u,
                ),
              ],
            ),
    );
  }
}
