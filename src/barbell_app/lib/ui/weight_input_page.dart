import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analysis/exercises.dart';
import '../workout/load_velocity.dart';
import '../workout/preferences.dart';
import '../workout/session.dart';
import 'app_scope.dart';
import 'app_theme.dart';
import 'app_widgets.dart';
import 'format.dart';
import 'record_set_page.dart';

/// Stance's `WeightInputRoute`: set type (four cells in two rows), then
/// weight, both required before each set. The unit comes from
/// Preferences.
///
/// Own addition: the weight starts at the exercise's last weight (Stance
/// starts empty).
class WeightInputPage extends StatefulWidget {
  const WeightInputPage({super.key, required this.exercise, this.session});

  final Exercise exercise;

  /// Session the set will be added to; null starts a new one.
  final Session? session;

  @override
  State<WeightInputPage> createState() => _WeightInputPageState();
}

class _WeightInputPageState extends State<WeightInputPage> {
  late final AppScope _app = AppScope.of(context);
  final _weight = TextEditingController();
  SetType? _setType;
  bool _prefilled = false;

  WeightUnit get _unit =>
      _app.preferences?.value.weightUnit ?? const Preferences().weightUnit;

  double? get _weightValue {
    final v = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    return v != null && v > 0 ? v : null;
  }

  bool get _canContinue => _weightValue != null && _setType != null;

  @override
  void initState() {
    super.initState();
    _weight.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    _app.sessions.lastWeight(widget.exercise.id).then((last) {
      if (!mounted || last == null || _weight.text.isNotEmpty) return;
      _weight.text = fmtNumber(convertWeight(last.weight, last.unit, _unit));
    });
  }

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  void _continue() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecordSetPage(
        exercise: widget.exercise,
        session: widget.session,
        weight: _weightValue!,
        unit: _unit,
        setType: _setType!,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unitName = _unit == WeightUnit.kg ? 'kilograms (kg)' : 'pounds (lb)';
    Widget gray(String text, TextStyle? style) =>
        Text(text, style: style?.copyWith(color: AppColors.subtitleGray));
    Widget setTypeRow(Iterable<SetType> types) => Row(children: [
          for (final (i, t) in types.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _SetTypeCell(
                key: ValueKey('setType-${t.key}'),
                label: t.displayName,
                selected: _setType == t,
                onTap: () => setState(() => _setType = t),
              ),
            ),
          ],
        ]);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            WorkoutTopBar(sensor: _app.sensor),
            Expanded(
              child: ListView(children: [
                const SizedBox(height: 24),
                gray(widget.exercise.rawValue, theme.textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text('Input weight', style: theme.textTheme.headlineLarge),
                const SizedBox(height: 8),
                gray('Choose Set Type to view your readiness before your Working set.',
                    theme.textTheme.bodyMedium),
                const SizedBox(height: 6),
                gray('This value is saved in $unitName.', theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                setTypeRow(SetType.values.take(2)),
                const SizedBox(height: 4),
                setTypeRow(SetType.values.skip(2)),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('weightField'),
                  controller: _weight,
                  autofocus: true,
                  style: theme.textTheme.bodyLarge.tabular,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Weight',
                    border: OutlineInputBorder(),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              child: AppButton(
                key: const Key('continue'),
                text: 'Continue',
                height: 48,
                onPressed: _canContinue ? _continue : null,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Stance's `SetTypeCell`: a 12 dp rounded cell at white 4 % with a
/// white 12 % outline, a 20 dp radio ring (green dot when chosen) and the
/// set type's name.
class _SetTypeCell extends StatelessWidget {
  const _SetTypeCell(
      {super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0x1FFFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: selected
                  ? Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: AppColors.connected),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ]),
        ),
      ),
    );
  }
}
