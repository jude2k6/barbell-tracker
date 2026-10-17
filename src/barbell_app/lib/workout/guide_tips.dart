import '../analysis/exercises.dart';
import 'preferences.dart';
import 'readiness.dart';
import 'session.dart';

/// Stance's feedback guide tips (notes §17): one short "Readiness" tip per
/// visit to the session page, each shown once ever.
class GuideTip {
  const GuideTip(this.guide, this.delay, this.message);

  final Guide guide;

  /// How long after the page settles the tip appears.
  final Duration delay;
  final String message;

  static const title = 'Readiness';
}

/// The first unseen tip that applies to [set], in Stance's order:
/// readiness, comparison (needs a last session), historical average (needs
/// several sessions), top set (a top set with several sessions).
/// [weightLabel] is the set's weight as displayed, e.g. "100 kg".
GuideTip? firstEligibleTip({
  required bool Function(Guide) hasSeen,
  required SetRecord set,
  required ReadinessResult readiness,
  required String weightLabel,
  String? dayTypeName,
}) {
  final speed = readinessSpeed(set);
  if (!hasSeen(Guide.readinessTip)) {
    return GuideTip(
      Guide.readinessTip,
      const Duration(milliseconds: 1000),
      speed == null
          ? 'Track your readiness by comparing your performance across sessions.'
          : 'You moved $weightLabel at ${speed.toStringAsFixed(2)}m/s. Next time '
              'you lift $weightLabel in your Primary session, you\'ll be able to '
              'compare.',
    );
  }
  final last = readiness.lastSessionSpeed;
  if (last != null && !hasSeen(Guide.comparisonTip)) {
    final String message;
    if (speed == null) {
      message = 'Compare your performance with previous sessions of the same weight.';
    } else {
      final d = speed - last;
      final diff = d.abs() < 0.005
          ? 'same speed'
          : '${d.abs().toStringAsFixed(2)}m/s ${d > 0 ? 'faster' : 'slower'}';
      final kind = dayTypeName == null ? 'session' : '$dayTypeName session';
      message = 'You can compare This Session with last $kind. You moved '
          '$weightLabel This Session $diff vs. Last Session.';
    }
    return GuideTip(Guide.comparisonTip, const Duration(milliseconds: 1500), message);
  }
  final several = readiness.historicAverage != null;
  if (several && !hasSeen(Guide.historicalAverageTip)) {
    return const GuideTip(
      Guide.historicalAverageTip,
      Duration(milliseconds: 2000),
      'Historical Average unlocked! Based on your last 90 days, using up to 12 '
      'of your most relevant sessions. Use it as another comparison point.',
    );
  }
  if (set.setType == SetType.topSet && several && !hasSeen(Guide.topSetTip)) {
    return const GuideTip(
      Guide.topSetTip,
      Duration(milliseconds: 3000),
      'Your Top Set is your session\'s key measure. This gauge helps you compare '
      'Today\'s speed with past sessions objectively.',
    );
  }
  return null;
}
