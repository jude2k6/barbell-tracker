import 'package:flutter/material.dart';

import '../analysis/exercises.dart';
import 'app_theme.dart';

/// Stance's Home catalogue: the root lists the three groups; a group
/// lists its exercises, with [DeadliftTipsCard] after the deadlift ones.
/// Rows for a parent [ListView] with 12 dp between them.
List<Widget> exerciseListChildren(
  BuildContext context, {
  required ExerciseFamily? group,
  required ValueChanged<ExerciseFamily> onGroup,
  required ValueChanged<Exercise> onExercise,
}) {
  final rows = group == null
      ? [
          for (final f in ExerciseFamily.values)
            ExerciseCatalogRow(
              key: ValueKey('group-${f.name}'),
              title: familyTitle(f),
              badge: familyBadge(f),
              onTap: () => onGroup(f),
            ),
        ]
      : [
          for (final e in Exercise.all.where((e) => e.family == group))
            ExerciseCatalogRow(
              key: ValueKey('exercise-${e.id}'),
              title: e.shortTitle,
              badge: familyBadge(e.family),
              onTap: () => onExercise(e),
            ),
          if (group == ExerciseFamily.deadlift) const DeadliftTipsCard(),
        ];
  return [
    for (final (i, row) in rows.indexed)
      Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 12), child: row),
  ];
}

String familyTitle(ExerciseFamily f) => switch (f) {
      ExerciseFamily.squat => 'Squat',
      ExerciseFamily.bench => 'Bench',
      ExerciseFamily.deadlift => 'Deadlift',
    };

/// Stance's `ExerciseCatalog` badges: only the deadlift group (and its
/// exercises) is BETA.
String? familyBadge(ExerciseFamily f) =>
    f == ExerciseFamily.deadlift ? 'BETA' : null;

/// Stance's `ExerciseCatalogRow`: a 16 dp card at 4 % white with the
/// exercise photo, the title and badge, and a bordered arrow box.
class ExerciseCatalogRow extends StatelessWidget {
  const ExerciseCatalogRow(
      {super.key, required this.title, this.badge, required this.onTap});

  final String title;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.cardFill,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset('assets/images/exercise_sample.png',
                    width: 48, height: 48, fit: BoxFit.cover),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(title,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (badge case final b?) _Badge(b),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 60,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x1AFFFFFF)),
                ),
                child: const Icon(Icons.arrow_forward, color: Colors.white),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Stance's `ExerciseBadge`.
class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w500, color: const Color(0x99FFFFFF))),
      );
}

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
    final body = Theme.of(context).textTheme.bodyLarge;
    return Container(
      key: const Key('deadliftTips'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tips:', style: body?.copyWith(fontWeight: FontWeight.w600)),
        for (final tip in deadliftTips) ...[
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('•', style: body),
            const SizedBox(width: 10),
            Expanded(child: Text(tip, style: body)),
          ]),
        ],
      ]),
    );
  }
}
