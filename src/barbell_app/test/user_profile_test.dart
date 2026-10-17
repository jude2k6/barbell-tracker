import 'dart:io';

import 'package:barbell_app/recording/recording.dart';
import 'package:barbell_app/ui/app_scope.dart';
import 'package:barbell_app/ui/home_page.dart';
import 'package:barbell_app/workout/preferences.dart';
import 'package:barbell_app/workout/sensor_controller.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:barbell_app/workout/session_store.dart';
import 'package:barbell_app/workout/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  group('rules (UserProfileEditorRules)', () {
    test('unit conversions round like Stance', () {
      expect(kgToLbs(100), 220);
      expect(lbsToKg(225), 102);
      expect(cmToFtIn(180), (5, 11));
      expect(ftInToCm(5, 11), 180);
      expect(cmToFtIn(183), (6, 0));
    });

    test('ranges', () {
      expect(validWeight(40, metric: true), isTrue);
      expect(validWeight(151, metric: true), isFalse);
      expect(validWeight(87, metric: false), isFalse);
      expect(validWeight(330, metric: false), isTrue);
      expect(validHeightCm(129), isFalse);
      expect(validHeightCm(230), isTrue);
      expect(validHeightFtIn(4, 3), isTrue);
      expect(validHeightFtIn(4, 2), isFalse);
      expect(validHeightFtIn(7, 6), isTrue);
      expect(validHeightFtIn(7, 7), isFalse);
      expect(validHeightFtIn(5, 12), isFalse);
    });

    test('completion counts nine fields; Instagram is not one', () {
      const empty = UserProfile();
      expect(empty.completion, 0);
      expect(empty.nextFieldToComplete, 'First Name');
      final p = empty.copyWith(
        firstName: 'Sam',
        lastName: 'Lee',
        weightKg: () => 90,
        instagramUsername: () => 'sam',
      );
      expect(completionLabel(p.completion), '33%');
      expect(p.nextFieldToComplete, 'Gender');
    });

    test('JSON round trip; blank Instagram is dropped on save', () {
      final p = const UserProfile().copyWith(
        firstName: 'Sam',
        gender: () => 'Other',
        dateOfBirth: () => DateTime(1995, 3, 7),
        weightKg: () => 83,
        heightCm: () => 178,
        trainingAge: () => 4,
        confidenceLevel: () => ConfidenceLevel.quiteConfident,
        competitionLevel: () => CompetitionLevel.none,
        instagramUsername: () => '  ',
      );
      final saved = p.normalized;
      expect(saved.instagramUsername, isNull);
      final back = UserProfile.fromJson(saved.toJson());
      expect(back, saved);
      expect(saved.toJson()['competitionLevel'], 'No');
      expect(saved.toJson()['dateOfBirth'], '1995-03-07');
      final prefs = Preferences(heightUnit: HeightUnit.ftIn, profile: saved);
      final again = Preferences.fromJson(prefs.toJson());
      expect(again.profile, saved);
      expect(again.heightUnit, HeightUnit.ftIn);
      expect(Preferences.fromJson(const {}).profile, const UserProfile());
    });
  });

  group('screens', () {
    late Directory dir;
    late PreferencesStore prefs;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('profile_test');
      prefs = PreferencesStore(baseDirectory: () async => dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Widget app() => AppScope(
      sensor: SensorController(),
      sessions: SessionStore(baseDirectory: () async => dir),
      recordings: RecordingStore(baseDirectory: () async => dir),
      preferences: prefs,
      child: const MaterialApp(home: HomePage()),
    );

    Future<void> openMenu(WidgetTester tester, String item) async {
      await tester.tap(find.byKey(const Key('homeMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    /// The sheet's list builds lazily, so scroll until [key] is built.
    Future<void> scrollTo(
      WidgetTester tester,
      Key key, {
      double delta = 150,
    }) async {
      await tester.scrollUntilVisible(
        find.byKey(key),
        delta,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('User Details: fields save with Save; weight in lbs is kept '
        'in kg and switches the app unit', (tester) async {
      await tester.pumpWidget(app());
      await openMenu(tester, 'User Details');
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('Add First Name for better insights'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('profileFirstName')),
          matching: find.byType(TextField),
        ),
        'Sam',
      );
      await tester.pump();
      expect(find.text('Hello Sam'), findsOneWidget);
      expect(find.text('11%'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);

      // Weight: switch to lbs, an out-of-range value shows the error and
      // keeps nothing, a valid one is stored in kg.
      await scrollTo(tester, const Key('profileWeightUnit'));
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('profileWeightUnit')),
          matching: find.text('lbs'),
        ),
      );
      await tester.pump();
      final weight = find.byKey(const ValueKey('profileWeight-false'));
      await tester.enterText(weight, '50');
      await tester.pump();
      expect(
        find.text('Enter a weight between 88 and 330 lbs'),
        findsOneWidget,
      );
      await tester.enterText(weight, '200');
      await tester.pump();
      expect(find.text('Enter a weight between 88 and 330 lbs'), findsNothing);

      // Height in feet and inches.
      await scrollTo(tester, const Key('profileHeightUnit'));
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('profileHeightUnit')),
          matching: find.text('ft'),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byKey(const Key('profileHeightFeet')), '5');
      await tester.pump();
      expect(
        find.text('Enter a height between 4\'3" and 7\'6"'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('profileHeightInches')),
        '10',
      );
      await tester.pump();
      expect(find.text('Enter a height between 4\'3" and 7\'6"'), findsNothing);

      // A picker.
      await scrollTo(tester, const Key('profileCompetition'));
      await tester.tap(find.byKey(const Key('profileCompetition')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regional').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profileSave')));
      await tester.pumpAndSettle();
      await _settleIo(tester);
      final saved = prefs.value;
      expect(saved.profile.firstName, 'Sam');
      expect(saved.profile.weightKg, 91);
      expect(saved.profile.heightCm, 178);
      expect(saved.profile.competitionLevel, CompetitionLevel.regional);
      expect(saved.weightUnit, WeightUnit.lb);
      expect(saved.heightUnit, HeightUnit.ftIn);

      // Reopened: values shown in the saved units; dismissing also saves.
      await openMenu(tester, 'User Details');
      expect(find.text('Hello Sam'), findsOneWidget);
      await scrollTo(tester, const Key('profileWeightUnit'));
      expect(find.widgetWithText(TextField, '201'), findsOneWidget);
      expect(find.widgetWithText(TextField, '5'), findsOneWidget);
      expect(find.widgetWithText(TextField, '10'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('profileWeightUnit')),
          matching: find.text('kg'),
        ),
      );
      await tester.pump();
      expect(find.widgetWithText(TextField, '91'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await _settleIo(tester);
      expect(prefs.value.weightUnit, WeightUnit.kg);
      expect(prefs.value.profile.weightKg, 91);
    });

    testWidgets('Preferences: units apply on Done; back discards', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await openMenu(tester, 'Preferences');
      await tester.tap(find.text('lb'));
      await tester.tap(find.text('ft-in'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(prefs.value.weightUnit, WeightUnit.kg);
      expect(prefs.value.heightUnit, HeightUnit.cm);

      await openMenu(tester, 'Preferences');
      expect(find.text('Customize your app experience'), findsOneWidget);
      await tester.tap(find.text('lb'));
      await tester.tap(find.text('ft-in'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('preferencesDone')));
      await tester.pumpAndSettle();
      await _settleIo(tester);
      expect(prefs.value.weightUnit, WeightUnit.lb);
      expect(prefs.value.heightUnit, HeightUnit.ftIn);
      expect(find.byKey(const Key('preferencesDone')), findsNothing);
    });
  });
}
