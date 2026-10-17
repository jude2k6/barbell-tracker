import 'package:flutter/material.dart';

import '../analysis/exercises.dart';

/// Exercise catalogue grouped by family (Squat / Bench / Deadlift), as
/// children for a parent [ListView].
List<Widget> exerciseListChildren(
    BuildContext context, ValueChanged<Exercise> onTap) {
  final theme = Theme.of(context);
  return [
    for (final family in ExerciseFamily.values) ...[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Row(children: [
          Icon(familyIcon(family), size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(familyTitle(family),
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
        ]),
      ),
      for (final e in Exercise.all.where((e) => e.family == family))
        ListTile(
          key: ValueKey('exercise-${e.id}'),
          title: Text(e.shortTitle),
          subtitle: Text(e.rawValue),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onTap(e),
        ),
      if (family == ExerciseFamily.deadlift) const DeadliftTipsCard(),
    ],
  ];
}

String familyTitle(ExerciseFamily f) => switch (f) {
      ExerciseFamily.squat => 'Squat',
      ExerciseFamily.bench => 'Bench',
      ExerciseFamily.deadlift => 'Deadlift',
    };

IconData familyIcon(ExerciseFamily f) => switch (f) {
      ExerciseFamily.squat => Icons.accessibility_new,
      ExerciseFamily.bench => Icons.airline_seat_flat,
      ExerciseFamily.deadlift => Icons.fitness_center,
    };

/// Stance's `home_deadlift_tip_*` strings, in its display order.
const deadliftTips = [
  'Pause between lifts (~1 second)',
  'Pause at the top of the lift (if possible ~ 1s)',
  "Stop the recording after you finished your lift (don't leave it recording)",
  'Move with intent',
  'Known limitation: This does not track tempo-based deadlifts.',
];

/// Stance's DeadliftTipsCard: "Tips:" and a bullet per tip, shown under
/// the deadlift exercises.
class DeadliftTipsCard extends StatelessWidget {
  const DeadliftTipsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        key: const Key('deadliftTips'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tips:', style: theme.textTheme.titleSmall),
                for (final tip in deadliftTips) ...[
                  const SizedBox(height: 12),
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('\u2022'),
                        const SizedBox(width: 10),
                        Expanded(child: Text(tip)),
                      ]),
                ],
              ]),
        ),
      ),
    );
  }
}
