import 'session.dart';

/// Summary numbers derived from a set's reps.
extension SetMetrics on List<RepRecord> {
  /// Fastest mean concentric velocity, m/s.
  double? get bestMeanVelocity => isEmpty
      ? null
      : map((r) => r.meanVelocity).reduce((a, b) => a > b ? a : b);

  /// Average mean concentric velocity, m/s.
  double? get avgMeanVelocity =>
      isEmpty ? null : map((r) => r.meanVelocity).reduce((a, b) => a + b) / length;

  /// Velocity loss from the fastest rep to the last rep, in percent
  /// (0 when the last rep is the fastest). Null with fewer than two reps.
  double? get velocityLossPct {
    if (length < 2) return null;
    final best = bestMeanVelocity!;
    if (best <= 0) return null;
    final loss = (best - last.meanVelocity) / best * 100;
    return loss < 0 ? 0 : loss;
  }
}

extension SessionMetrics on Session {
  /// Fastest rep mean velocity across all sets.
  double? get bestMeanVelocity {
    double? best;
    for (final s in sets) {
      final b = s.reps.bestMeanVelocity;
      if (b != null && (best == null || b > best)) best = b;
    }
    return best;
  }
}
