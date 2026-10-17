import 'package:flutter/material.dart';

import '../workout/preferences.dart';
import '../workout/session.dart';
import '../workout/user_profile.dart';
import 'app_scope.dart';
import 'app_theme.dart';
import 'app_widgets.dart';

/// Stance's `PreferencesScreen`: weight unit (used for weight input) and height
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
    return Scaffold(
      body: SafeArea(
        child: _store == null
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          'Preferences',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        AppSmallButton(
                          'Done',
                          key: const Key('preferencesDone'),
                          secondary: true,
                          onPressed: _done,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Customize your app experience',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.gray,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _UnitSection<WeightUnit>(
                      title: 'Weight Unit',
                      rowKey: const Key('weightUnitPreference'),
                      options: const [(WeightUnit.kg, 'kg'), (WeightUnit.lb, 'lb')],
                      selected: _weight,
                      onSelected: (u) => setState(() => _weight = u),
                      hint:
                          'This preference will be used for exercise weight '
                          'input.',
                    ),
                    const SizedBox(height: 16),
                    _UnitSection<HeightUnit>(
                      title: 'Height Unit',
                      rowKey: const Key('heightUnitPreference'),
                      options: const [(HeightUnit.cm, 'cm'), (HeightUnit.ftIn, 'ft-in')],
                      selected: _height,
                      onSelected: (u) => setState(() => _height = u),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Stance's `ProfileSectionCard`: black at 30 %, 16 dp radius and padding.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0x4D000000),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// A `ProfileSectionCard` with a title and a row of [_UnitOptionRow]s.
class _UnitSection<T> extends StatelessWidget {
  const _UnitSection({
    required this.title,
    required this.rowKey,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.hint,
  });

  final String title;
  final Key rowKey;
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          key: rowKey,
          children: [
            for (final (i, (v, label)) in options.indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: _UnitOptionRow(
                  label: label,
                  selected: v == selected,
                  onTap: () => onSelected(v),
                ),
              ),
            ],
          ],
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.gray),
            ),
          ),
      ],
    );
  }
}

/// Stance's `UnitOptionRow`: a 12 dp pill at 4 % white with a check circle
/// (primary) or an outlined circle (gray) and a semi-bold titleMedium label.
class _UnitOptionRow extends StatelessWidget {
  const _UnitOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.cardFill,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? AppColors.primary : AppColors.gray,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
}
