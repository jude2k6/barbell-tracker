import 'package:flutter/material.dart';

import '../workout/preferences.dart';
import '../workout/session.dart';
import '../workout/user_profile.dart';
import 'format.dart';

/// The profile being edited plus the two unit preferences, which Stance's
/// weight and height fields switch too (`UserProfileEditorRules.Draft`).
@immutable
class ProfileDraft {
  const ProfileDraft(this.profile, this.weightUnit, this.heightUnit);

  ProfileDraft.of(Preferences p) : this(p.profile, p.weightUnit, p.heightUnit);

  final UserProfile profile;
  final WeightUnit weightUnit;
  final HeightUnit heightUnit;

  bool get metricWeight => weightUnit == WeightUnit.kg;
  bool get metricHeight => heightUnit == HeightUnit.cm;

  ProfileDraft copyWith({
    UserProfile? profile,
    WeightUnit? weightUnit,
    HeightUnit? heightUnit,
  }) => ProfileDraft(
    profile ?? this.profile,
    weightUnit ?? this.weightUnit,
    heightUnit ?? this.heightUnit,
  );

  /// Stance's `hasChanges`, against the saved preferences.
  bool differsFrom(Preferences p) =>
      profile.normalized != p.profile ||
      weightUnit != p.weightUnit ||
      heightUnit != p.heightUnit;

  Preferences applyTo(Preferences p) => p.copyWith(
    profile: profile.normalized,
    weightUnit: weightUnit,
    heightUnit: heightUnit,
  );
}

/// Stance's `UserDetailsSheet` ("User Details" in the Home menu). Its
/// Save/Done button and dismissing the sheet both save.
Future<void> showUserDetailsSheet(
  BuildContext context,
  PreferencesStore store,
) async {
  var draft = ProfileDraft.of(store.value);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.95,
      child: UserDetailsEditor(
        initial: draft,
        saved: store.value,
        onChanged: (d) => draft = d,
      ),
    ),
  );
  if (draft.differsFrom(store.value)) {
    await store.update(draft.applyTo(store.value));
  }
}

class UserDetailsEditor extends StatefulWidget {
  const UserDetailsEditor({
    super.key,
    required this.initial,
    required this.saved,
    required this.onChanged,
  });

  final ProfileDraft initial;

  /// The stored preferences, for Save versus Done.
  final Preferences saved;
  final ValueChanged<ProfileDraft> onChanged;

  @override
  State<UserDetailsEditor> createState() => _UserDetailsEditorState();
}

class _UserDetailsEditorState extends State<UserDetailsEditor> {
  late ProfileDraft _draft = widget.initial;

  UserProfile get _p => _draft.profile;

  void _set(ProfileDraft d) {
    setState(() => _draft = d);
    widget.onChanged(d);
  }

  void _profile(UserProfile p) => _set(_draft.copyWith(profile: p));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = _p.nextFieldToComplete;
    return Column(
      children: [
        // Header stays put while the fields scroll.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Hello',
                    children: [
                      if (_p.firstName.trim().isNotEmpty)
                        TextSpan(
                          text: ' ${_p.firstName}',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                    ],
                  ),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              FilledButton(
                key: const Key('profileSave'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_draft.differsFrom(widget.saved) ? 'Save' : 'Done'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            children: [
              const SizedBox(height: 12),
              Text('Profile', style: theme.textTheme.titleMedium),
              Text(
                'Complete your profile to get insights and recommendations more '
                'personalised to you.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              // Stance's `ProfileCompletionHeader`.
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(value: _p.completion),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    completionLabel(_p.completion),
                    key: const Key('profileCompletion'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              if (next != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Add $next for better insights',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              _TextField(
                key: const Key('profileFirstName'),
                label: 'First Name',
                description: 'Your first name',
                hint: 'Enter first name',
                value: _p.firstName,
                onChanged: (v) => _profile(_p.copyWith(firstName: v)),
              ),
              _TextField(
                key: const Key('profileLastName'),
                label: 'Last Name',
                description: 'Your last name',
                hint: 'Enter last name',
                value: _p.lastName,
                onChanged: (v) => _profile(_p.copyWith(lastName: v)),
              ),
              _Picker<String>(
                key: const Key('profileGender'),
                label: 'Gender',
                hint: 'Select Gender',
                value: _p.gender,
                options: {for (final g in genders) g: g},
                onChanged: (v) => _profile(_p.copyWith(gender: () => v)),
              ),
              _DateField(
                value: _p.dateOfBirth,
                onChanged: (v) => _profile(_p.copyWith(dateOfBirth: () => v)),
              ),
              _WeightField(
                weightKg: _p.weightKg,
                metric: _draft.metricWeight,
                onChanged: (kg) => _profile(_p.copyWith(weightKg: () => kg)),
                onMetric: (m) => _set(
                  _draft.copyWith(
                    weightUnit: m ? WeightUnit.kg : WeightUnit.lb,
                  ),
                ),
              ),
              _HeightField(
                heightCm: _p.heightCm,
                metric: _draft.metricHeight,
                onChanged: (cm) => _profile(_p.copyWith(heightCm: () => cm)),
                onMetric: (m) => _set(
                  _draft.copyWith(
                    heightUnit: m ? HeightUnit.cm : HeightUnit.ftIn,
                  ),
                ),
              ),
              _Picker<int>(
                key: const Key('profileTrainingAge'),
                label: 'Training Age (years)',
                description: 'How long have you been powerlifting?',
                hint: 'Select Training Age',
                value: _p.trainingAge,
                options: {for (var y = 0; y <= trainingAgeMax; y++) y: '$y'},
                onChanged: (v) => _profile(_p.copyWith(trainingAge: () => v)),
              ),
              _Picker<ConfidenceLevel>(
                key: const Key('profileConfidence'),
                label: 'RPE Confidence Level',
                description: 'How confident are you in judging your RPE?',
                hint: 'Select Confidence Level',
                value: _p.confidenceLevel,
                options: {
                  for (final c in ConfidenceLevel.values) c: c.rawValue,
                },
                onChanged: (v) =>
                    _profile(_p.copyWith(confidenceLevel: () => v)),
              ),
              _Picker<CompetitionLevel>(
                key: const Key('profileCompetition'),
                label: 'Competition Level',
                description: 'Have you competed in powerlifting before and if so what level?',
                hint: 'Select Competition Level',
                value: _p.competitionLevel,
                options: {
                  for (final c in CompetitionLevel.values) c: c.rawValue,
                },
                onChanged: (v) =>
                    _profile(_p.copyWith(competitionLevel: () => v)),
              ),
              const SizedBox(height: 8),
              Text('Optional Information', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _TextField(
                key: const Key('profileInstagram'),
                label: 'Instagram Username',
                description:
                    'Connect your Instagram profile (completely optional)',
                hint: 'Enter Instagram username',
                value: _p.instagramUsername ?? '',
                onChanged: (v) =>
                    _profile(_p.copyWith(instagramUsername: () => v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A labelled card-like block, like Stance's profile section fields.
class _Field extends StatelessWidget {
  const _Field({required this.label, this.description, required this.child});

  final String label;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          if (description != null)
            Text(description!, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    super.key,
    required this.label,
    required this.description,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label, description, hint, value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => _Field(
    label: label,
    description: description,
    child: TextFormField(
      initialValue: value,
      decoration: InputDecoration(
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      textCapitalization: TextCapitalization.words,
      onChanged: onChanged,
    ),
  );
}

class _Picker<T> extends StatelessWidget {
  const _Picker({
    super.key,
    required this.label,
    this.description,
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label, hint;
  final String? description;
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => _Field(
    label: label,
    description: description,
    child: DropdownButtonFormField<T>(
      initialValue: value,
      hint: Text(hint),
      isExpanded: true,
      decoration: const InputDecoration(border: OutlineInputBorder()),
      items: [
        for (final MapEntry(:key, value: text) in options.entries)
          DropdownMenuItem(value: key, child: Text(text)),
      ],
      onChanged: onChanged,
    ),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onChanged});

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) => _Field(
    label: 'Date of Birth',
    child: OutlinedButton(
      key: const Key('profileDateOfBirth'),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size.fromHeight(48),
      ),
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime(now.year - 25, now.month, now.day),
          firstDate: DateTime(1900),
          lastDate: now,
        );
        if (picked != null) onChanged(picked);
      },
      child: Text(value == null ? 'Select date' : fmtDate(value!)),
    ),
  );
}

/// Stance's `ProfileNumericField`: digits only; an empty field clears the
/// value, an out-of-range one shows the error and keeps the last valid
/// value. Keyed by unit, so a unit switch restarts it from the value.
class _NumberInput extends StatefulWidget {
  const _NumberInput({
    super.key,
    required this.value,
    required this.hint,
    required this.isValid,
    required this.error,
    required this.onChanged,
  });

  final int? value;
  final String hint, error;
  final bool Function(int) isValid;
  final ValueChanged<int?> onChanged;

  @override
  State<_NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<_NumberInput> {
  late final _controller = TextEditingController(text: _text(widget.value));

  static String _text(int? v) => v?.toString() ?? '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(_controller.text);
    final invalid =
        _controller.text.isNotEmpty && (n == null || !widget.isValid(n));
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        hintText: widget.hint,
        errorText: invalid ? widget.error : null,
        border: const OutlineInputBorder(),
      ),
      onChanged: (raw) {
        final digits = raw.replaceAll(RegExp(r'\D'), '');
        if (digits != raw) _controller.text = digits;
        setState(() {});
        final v = int.tryParse(digits);
        if (digits.isEmpty) {
          widget.onChanged(null);
        } else if (v != null && widget.isValid(v)) {
          widget.onChanged(v);
        }
      },
    );
  }
}

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({
    super.key,
    required this.labels,
    required this.metric,
    required this.onMetric,
  });

  final (String, String) labels;
  final bool metric;
  final ValueChanged<bool> onMetric;

  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
    segments: [
      ButtonSegment(value: true, label: Text(labels.$1)),
      ButtonSegment(value: false, label: Text(labels.$2)),
    ],
    selected: {metric},
    showSelectedIcon: false,
    onSelectionChanged: (s) => onMetric(s.first),
  );
}

/// Stance's `ProfileWeightField`: bodyweight in kg or lbs, stored as whole
/// kg; the toggle also switches the app's weight unit.
class _WeightField extends StatelessWidget {
  const _WeightField({
    required this.weightKg,
    required this.metric,
    required this.onChanged,
    required this.onMetric,
  });

  final int? weightKg;
  final bool metric;
  final ValueChanged<int?> onChanged;
  final ValueChanged<bool> onMetric;

  @override
  Widget build(BuildContext context) {
    final kg = weightKg;
    final shown = kg == null || metric ? kg : kgToLbs(kg);
    final (min, max) = metric
        ? (weightKgMin, weightKgMax)
        : (weightLbsMin, weightLbsMax);
    final unit = metric ? 'kg' : 'lbs';
    return _Field(
      label: 'Weight',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _NumberInput(
              key: ValueKey('profileWeight-$metric'),
              value: shown,
              hint: 'Enter weight ($unit)',
              isValid: (v) => validWeight(v, metric: metric),
              error: 'Enter a weight between $min and $max $unit',
              onChanged: (v) => onChanged(v == null || metric ? v : lbsToKg(v)),
            ),
          ),
          const SizedBox(width: 8),
          _UnitToggle(
            key: const Key('profileWeightUnit'),
            labels: const ('kg', 'lbs'),
            metric: metric,
            onMetric: onMetric,
          ),
        ],
      ),
    );
  }
}

/// Stance's `ProfileHeightField`: cm, or feet and inches; the toggle also
/// switches the height unit preference.
class _HeightField extends StatelessWidget {
  const _HeightField({
    required this.heightCm,
    required this.metric,
    required this.onChanged,
    required this.onMetric,
  });

  final int? heightCm;
  final bool metric;
  final ValueChanged<int?> onChanged;
  final ValueChanged<bool> onMetric;

  @override
  Widget build(BuildContext context) => _Field(
    label: 'Height',
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: metric
              ? _NumberInput(
                  key: const Key('profileHeightCm'),
                  value: heightCm,
                  hint: 'Enter height (cm)',
                  isValid: validHeightCm,
                  error:
                      'Enter a height between $heightCmMin and $heightCmMax cm',
                  onChanged: onChanged,
                )
              : _FeetInches(heightCm: heightCm, onChanged: onChanged),
        ),
        const SizedBox(width: 8),
        _UnitToggle(
          key: const Key('profileHeightUnit'),
          labels: const ('cm', 'ft'),
          metric: metric,
          onMetric: onMetric,
        ),
      ],
    ),
  );
}

class _FeetInches extends StatefulWidget {
  const _FeetInches({required this.heightCm, required this.onChanged});

  final int? heightCm;
  final ValueChanged<int?> onChanged;

  @override
  State<_FeetInches> createState() => _FeetInchesState();
}

class _FeetInchesState extends State<_FeetInches> {
  late final TextEditingController _feet, _inches;

  @override
  void initState() {
    super.initState();
    final cm = widget.heightCm;
    final (f, i) = cm == null ? (null, null) : cmToFtIn(cm);
    _feet = TextEditingController(text: f?.toString() ?? '');
    _inches = TextEditingController(text: i?.toString() ?? '');
  }

  @override
  void dispose() {
    _feet.dispose();
    _inches.dispose();
    super.dispose();
  }

  bool get _bothEmpty => _feet.text.isEmpty && _inches.text.isEmpty;

  bool get _valid {
    final f = int.tryParse(_feet.text), i = int.tryParse(_inches.text);
    return f != null && i != null && validHeightFtIn(f, i);
  }

  void _changed() {
    setState(() {});
    if (_bothEmpty) {
      widget.onChanged(null);
    } else if (_valid) {
      widget.onChanged(
        ftInToCm(int.parse(_feet.text), int.parse(_inches.text)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _bothEmpty || _valid
        ? null
        : 'Enter a height between 4\'3" and 7\'6"';
    Widget box(Key key, TextEditingController c, String label) => Expanded(
      child: TextField(
        key: key,
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: (raw) {
          final digits = raw.replaceAll(RegExp(r'\D'), '');
          if (digits != raw) c.text = digits;
          _changed();
        },
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            box(const Key('profileHeightFeet'), _feet, 'Feet'),
            const SizedBox(width: 8),
            box(const Key('profileHeightInches'), _inches, 'In'),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
