/// The user's profile, ported from Stance's `UserData`,
/// `UserProfileEditorRules` and the User Details sheet (notes §20).
/// Stance only stores and syncs it; no analysis reads it.
library;

import 'package:flutter/foundation.dart';

/// Stance's `CompetitionLevel`, with its stored raw values.
enum CompetitionLevel {
  none('No'),
  unsanctioned('Unsanctioned'),
  regional('Regional'),
  national('National'),
  international('International');

  const CompetitionLevel(this.rawValue);
  final String rawValue;

  static CompetitionLevel? fromRaw(String? raw) =>
      values.where((c) => c.rawValue == raw?.trim()).firstOrNull;
}

/// Stance's `ConfidenceLevel` ("RPE Confidence Level").
enum ConfidenceLevel {
  dontUse("I don't use RPE"),
  notConfident('Not Confident'),
  quiteConfident('Quite Confident'),
  confident('Confident'),
  veryConfident('Very Confident');

  const ConfidenceLevel(this.rawValue);
  final String rawValue;

  static ConfidenceLevel? fromRaw(String? raw) =>
      values.where((c) => c.rawValue == raw?.trim()).firstOrNull;
}

/// Stance's height unit preference (`cm` or `ft`, shown as "ft-in").
enum HeightUnit {
  cm,
  ftIn;

  static HeightUnit fromName(String? name) =>
      values.firstWhere((u) => u.name == name, orElse: () => cm);
}

const genders = ['Male', 'Female', 'Other'];

// Stance's input ranges. Weight and height are whole numbers, stored in kg
// and cm.
const weightKgMin = 40, weightKgMax = 150;
const weightLbsMin = 88, weightLbsMax = 330;
const heightCmMin = 130, heightCmMax = 230;
const heightInchesMin = 51, heightInchesMax = 90; // 4'3" to 7'6"
const trainingAgeMax = 50;

const _lbPerKg = 2.20462;
const _cmPerInch = 2.54;

int kgToLbs(int kg) => (kg * _lbPerKg).round();
int lbsToKg(int lbs) => (lbs / _lbPerKg).round();

/// Feet and inches for [cm] (`cmToFtIn`).
(int, int) cmToFtIn(int cm) {
  final inches = (cm / _cmPerInch).round();
  return (inches ~/ 12, inches % 12);
}

int ftInToCm(int feet, int inches) =>
    ((feet * 12 + inches) * _cmPerInch).round();

bool validWeight(int value, {required bool metric}) => metric
    ? value >= weightKgMin && value <= weightKgMax
    : value >= weightLbsMin && value <= weightLbsMax;

bool validHeightCm(int cm) => cm >= heightCmMin && cm <= heightCmMax;

bool validHeightFtIn(int feet, int inches) {
  final total = feet * 12 + inches;
  return inches >= 0 &&
      inches < 12 &&
      total >= heightInchesMin &&
      total <= heightInchesMax;
}

@immutable
class UserProfile {
  const UserProfile({
    this.firstName = '',
    this.lastName = '',
    this.gender,
    this.dateOfBirth,
    this.weightKg,
    this.heightCm,
    this.trainingAge,
    this.confidenceLevel,
    this.competitionLevel,
    this.instagramUsername,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    firstName: j['firstName'] as String? ?? '',
    lastName: j['lastName'] as String? ?? '',
    gender: j['gender'] as String?,
    dateOfBirth: switch (j['dateOfBirth']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    },
    weightKg: j['weightKg'] as int?,
    heightCm: j['heightCm'] as int?,
    trainingAge: j['trainingAge'] as int?,
    confidenceLevel: ConfidenceLevel.fromRaw(j['confidenceLevel'] as String?),
    competitionLevel: CompetitionLevel.fromRaw(
      j['competitionLevel'] as String?,
    ),
    instagramUsername: j['instagramUsername'] as String?,
  );

  final String firstName, lastName;
  final String? gender;
  final DateTime? dateOfBirth;

  /// Bodyweight, whole kg.
  final int? weightKg;
  final int? heightCm;

  /// Years of powerlifting.
  final int? trainingAge;
  final ConfidenceLevel? confidenceLevel;
  final CompetitionLevel? competitionLevel;
  final String? instagramUsername;

  /// Field setters for the editor; `null` clears a field.
  UserProfile copyWith({
    String? firstName,
    String? lastName,
    ValueGetter<String?>? gender,
    ValueGetter<DateTime?>? dateOfBirth,
    ValueGetter<int?>? weightKg,
    ValueGetter<int?>? heightCm,
    ValueGetter<int?>? trainingAge,
    ValueGetter<ConfidenceLevel?>? confidenceLevel,
    ValueGetter<CompetitionLevel?>? competitionLevel,
    ValueGetter<String?>? instagramUsername,
  }) => UserProfile(
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    gender: gender == null ? this.gender : gender(),
    dateOfBirth: dateOfBirth == null ? this.dateOfBirth : dateOfBirth(),
    weightKg: weightKg == null ? this.weightKg : weightKg(),
    heightCm: heightCm == null ? this.heightCm : heightCm(),
    trainingAge: trainingAge == null ? this.trainingAge : trainingAge(),
    confidenceLevel: confidenceLevel == null
        ? this.confidenceLevel
        : confidenceLevel(),
    competitionLevel: competitionLevel == null
        ? this.competitionLevel
        : competitionLevel(),
    instagramUsername: instagramUsername == null
        ? this.instagramUsername
        : instagramUsername(),
  );

  /// As saved (`toUserData`): a blank Instagram name is dropped.
  UserProfile get normalized => copyWith(
    instagramUsername: () {
      final s = instagramUsername?.trim();
      return s == null || s.isEmpty ? null : s;
    },
  );

  Map<String, dynamic> toJson() => {
    if (firstName.isNotEmpty) 'firstName': firstName,
    if (lastName.isNotEmpty) 'lastName': lastName,
    'gender': ?gender,
    if (dateOfBirth case final d?)
      'dateOfBirth':
          '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}',
    'weightKg': ?weightKg,
    'heightCm': ?heightCm,
    'trainingAge': ?trainingAge,
    'confidenceLevel': ?confidenceLevel?.rawValue,
    'competitionLevel': ?competitionLevel?.rawValue,
    'instagramUsername': ?instagramUsername,
  };

  /// The nine fields Stance counts towards completion, in its order, with
  /// whether each is filled. Instagram is optional and not counted.
  List<(String, bool)> get _completionFields => [
    ('First Name', firstName.trim().isNotEmpty),
    ('Last Name', lastName.trim().isNotEmpty),
    ('Gender', gender != null),
    ('Date of Birth', dateOfBirth != null),
    ('Weight', weightKg != null),
    ('Height', heightCm != null),
    ('Training Age', trainingAge != null),
    ('Confidence Level', confidenceLevel != null),
    ('Competition Level', competitionLevel != null),
  ];

  /// `completionPercentage`: filled fields out of nine.
  double get completion =>
      _completionFields.where((f) => f.$2).length / _completionFields.length;

  /// `nextFieldToComplete`: the first empty field, or null.
  String? get nextFieldToComplete =>
      _completionFields.where((f) => !f.$2).firstOrNull?.$1;

  @override
  bool operator ==(Object other) =>
      other is UserProfile && mapEquals(toJson(), other.toJson());

  @override
  int get hashCode => Object.hashAllUnordered(
    toJson().entries.map((e) => Object.hash(e.key, e.value)),
  );
}

/// Whole-percent label for the completion bar: Stance truncates.
String completionLabel(double completion) => '${(100 * completion).toInt()}%';
