import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analysis/exercises.dart';
import '../workout/load_velocity.dart';
import '../workout/preferences.dart';
import '../workout/session.dart';
import 'app_scope.dart';
import 'format.dart';
import 'record_set_page.dart';
import 'sensor_status_chip.dart';
import 'workout_flow.dart';

/// Stance's weight input: weight and a set type, both required, before
/// each set. The unit comes from Preferences.
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Input weight'),
        actions: [
          SensorStatusChip(sensor: _app.sensor, onPressed: () => openDevice(context)),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.exercise.rawValue, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Choose Set Type to view your readiness before your Working set.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextField(
            key: const Key('weightField'),
            controller: _weight,
            autofocus: true,
            style: theme.textTheme.titleLarge.tabular,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: 'Weight',
              suffixText: _unit.name,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text('This value is saved in $unitName.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Text('Set Type', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final t in SetType.values)
              ChoiceChip(
                key: ValueKey('setType-${t.key}'),
                label: Text(t.displayName),
                selected: _setType == t,
                onSelected: (on) => setState(() => _setType = on ? t : null),
              ),
          ]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            key: const Key('continue'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _canContinue ? _continue : null,
            child: const Text('Continue'),
          ),
        ),
      ),
    );
  }
}
