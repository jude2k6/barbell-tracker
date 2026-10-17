import 'package:flutter/material.dart';

import '../workout/preferences.dart';
import '../workout/session.dart';
import '../workout/user_profile.dart';
import 'app_theme.dart';
import 'app_widgets.dart';
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
    backgroundColor: _sheetColor,
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
    const gap = SizedBox(height: 12);
    return Column(
      children: [
        // Header stays put while the fields scroll.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                          style: const TextStyle(color: AppColors.primary),
                        ),
                    ],
                  ),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              AppSmallButton(
                _draft.differsFrom(widget.saved) ? 'Save' : 'Done',
                key: const Key('profileSave'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            children: [
              Text(
                'Profile',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: Text(
                  'Complete your profile to get insights and recommendations '
                  'more personalised to you.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.gray),
                ),
              ),
              // Stance's `ProfileCompletionHeader`.
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _p.completion,
                          color: AppColors.primary,
                          backgroundColor: const Color(0x1AFFFFFF),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    completionLabel(_p.completion),
                    key: const Key('profileCompletion'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              if (next != null)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary),
                  ),
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
              gap,
              _TextField(
                key: const Key('profileLastName'),
                label: 'Last Name',
                description: 'Your last name',
                hint: 'Enter last name',
                value: _p.lastName,
                onChanged: (v) => _profile(_p.copyWith(lastName: v)),
              ),
              gap,
              _Picker<String>(
                fieldKey: const Key('profileGender'),
                label: 'Gender',
                hint: 'Select Gender',
                value: _p.gender,
                options: {for (final g in genders) g: g},
                onChanged: (v) => _profile(_p.copyWith(gender: () => v)),
              ),
              gap,
              _DateField(
                value: _p.dateOfBirth,
                onChanged: (v) => _profile(_p.copyWith(dateOfBirth: () => v)),
              ),
              gap,
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
              gap,
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
              gap,
              _Picker<int>(
                fieldKey: const Key('profileTrainingAge'),
                label: 'Training Age (years)',
                description: 'How long have you been powerlifting?',
                hint: 'Select Training Age',
                value: _p.trainingAge,
                options: {for (var y = 0; y <= trainingAgeMax; y++) y: '$y'},
                onChanged: (v) => _profile(_p.copyWith(trainingAge: () => v)),
              ),
              gap,
              _Picker<ConfidenceLevel>(
                fieldKey: const Key('profileConfidence'),
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
              gap,
              _Picker<CompetitionLevel>(
                fieldKey: const Key('profileCompetition'),
                label: 'Competition Level',
                description:
                    'Have you competed in powerlifting before and if so what '
                    'level?',
                hint: 'Select Competition Level',
                value: _p.competitionLevel,
                options: {
                  for (final c in CompetitionLevel.values) c: c.rawValue,
                },
                onChanged: (v) =>
                    _profile(_p.copyWith(competitionLevel: () => v)),
              ),
              const SizedBox(height: 16),
              Divider(color: AppColors.gray.withValues(alpha: 0.4)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Optional Information',
                  style: theme.textTheme.titleMedium?.copyWith(color: AppColors.gray),
                ),
              ),
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
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

/// Stance's sheet container colour.
const _sheetColor = Color(0xFF101010);

/// Stance's `stanceCard`: 20 dp radius, white 4 % fill, 1 dp white 12 %
/// border, 16 dp padding.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.cardFill,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0x1FFFFFFF)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

/// The `OutlinedTextField` colours Stance's profile fields share: white
/// text, primary cursor and focused border, gray 50 % border and gray hint.
InputDecoration _decoration({String? hint, String? label, String? error}) {
  OutlineInputBorder border(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: BorderSide(color: c),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.gray),
    labelText: label,
    errorText: error,
    enabledBorder: border(AppColors.gray.withValues(alpha: 0.5)),
    focusedBorder: border(AppColors.primary),
    errorBorder: border(AppColors.error),
    focusedErrorBorder: border(AppColors.error),
  );
}

/// Stance's profile field card: a titleMedium [label], an optional gray
/// [description], then the [child].
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    this.description,
    this.trailing,
    this.onTap,
    required this.child,
  });

  final String label;
  final String? description;

  /// Shown at the end of the label row (the unit tabs).
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Card(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
              ?trailing,
            ],
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                description!,
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.gray),
              ),
            ),
          Padding(padding: const EdgeInsets.only(top: 8), child: child),
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
      cursorColor: AppColors.primary,
      decoration: _decoration(hint: hint),
      textCapitalization: TextCapitalization.words,
      onChanged: onChanged,
    ),
  );
}

/// Stance's `ProfilePickerField` with `StanceMenuPicker`: a box (8 dp
/// radius, gray 50 % border, semi-bold value, down arrow) opening a menu.
class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.fieldKey,
    required this.label,
    this.description,
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label, hint;
  final String? description;
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Field(
      label: label,
      description: description,
      child: Align(
        alignment: Alignment.centerRight,
        child: AppMenuPicker<T>(
          key: fieldKey,
          value: value,
          values: options.keys.toList(),
          label: (v) => options[v]!,
          hint: hint,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onChanged});

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: const Key('profileDateOfBirth'),
    child: _Field(
      label: 'Date of Birth',
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime(now.year - 25, now.month, now.day),
          firstDate: DateTime(1900),
          lastDate: now,
        );
        if (picked != null) onChanged(picked);
      },
      child: Text(
        value == null ? 'Select date' : fmtDate(value!),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
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
      cursorColor: AppColors.primary,
      decoration: _decoration(
        hint: widget.hint,
        error: invalid ? widget.error : null,
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
      trailing: AppSegmentedTabs<bool>(
        key: const Key('profileWeightUnit'),
        width: 100,
        values: const [true, false],
        selected: metric,
        label: (m) => m ? 'kg' : 'lbs',
        onSelect: onMetric,
      ),
      child: _NumberInput(
        key: ValueKey('profileWeight-$metric'),
        value: shown,
        hint: 'Enter weight ($unit)',
        isValid: (v) => validWeight(v, metric: metric),
        error: 'Enter a weight between $min and $max $unit',
        onChanged: (v) => onChanged(v == null || metric ? v : lbsToKg(v)),
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
    trailing: AppSegmentedTabs<bool>(
      key: const Key('profileHeightUnit'),
      width: 100,
      values: const [true, false],
      selected: metric,
      label: (m) => m ? 'cm' : 'ft',
      onSelect: onMetric,
    ),
    child: metric
        ? _NumberInput(
            key: const Key('profileHeightCm'),
            value: heightCm,
            hint: 'Enter height (cm)',
            isValid: validHeightCm,
            error: 'Enter a height between $heightCmMin and $heightCmMax cm',
            onChanged: onChanged,
          )
        : _FeetInches(heightCm: heightCm, onChanged: onChanged),
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
        cursorColor: AppColors.primary,
        decoration: _decoration(label: label),
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
            const SizedBox(width: 12),
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
