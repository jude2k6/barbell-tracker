import 'package:flutter/material.dart';

import '../analysis/exercises.dart';
import '../workout/guide_tips.dart';

/// Stance's step-by-step guides (notes §17), shown in a paging dialog.
class GuideStep {
  const GuideStep(this.title, this.body);
  final String title, body;
}

/// `FEEDBACK_WALKTHROUGH_STEPS`, word for word.
const feedbackWalkthroughSteps = [
  GuideStep('Congrats on your First Set!',
      "Let's quickly walk you through the app so you know how to get the most out of it."),
  GuideStep('First up, check the Rep Count',
      'If this isn\'t right, hit "Edit" and change the reps and the app will '
          're-calculate and find the right reps.'),
  GuideStep('Here are your reps',
      "Here's the bar-speed of each rep in the set. Compare the speed within a set "
          'and also between sets.'),
  GuideStep('Assess your readiness',
      'This number is the fastest rep in the set and the best indicator of your '
          'readiness for that weight. When you lift this weight in future sessions, '
          'use this number for comparisons.'),
  GuideStep('Toggle fastest and last',
      'Your last rep speed is the best indicator of your RPE. See how the last rep '
          'speed compares over time for the same weight and reps. If it\'s faster, '
          "you're getting stronger/your RPE is lower! If not, it may be a sign of "
          'fatigue.'),
  GuideStep('Session Profile',
      'The fastest rep of a set is plotted on this weight-speed chart. 1 data point '
          'per set. \nAs the load increases during the session, see how your '
          'bar-speed drops.'),
  GuideStep('Comparing Sessions',
      'Compare this profile with previous sessions to assess progress and fatigue.'),
];

/// Stance's rep edit guide, minus its "only works for sets with a video
/// recording" note: our Rep Check works from the velocity trace alone.
const repEditGuideSteps = [
  GuideStep('Manually edit your reps.', 'Use this tool to fix your reps manually.'),
  GuideStep('Delete, add and edit reps',
      'This tool allows you to delete specific reps, add reps, and edit the '
          'concentric start and end times of reps.'),
  GuideStep('Identifying reps',
      'R1s and R1e indicate the start and end point of the concentric part of a rep '
          'so you know which one to edit.'),
  GuideStep('Deleting reps', 'Identify the incorrect rep and delete.'),
  GuideStep('Editing reps',
      'Identify where the rep concentric start/end should actually be and adjust '
          'accordingly.\nRemember, to mark the concentric start and end of a rep, not '
          'the entire rep (eccentric + concentric).'),
  GuideStep('Adding reps',
      'Mark the start and end of the concentric part of the misidentified rep and '
          'hit save.'),
];

/// Stance's pre-recording guide. Its three Stance-tracker hardware steps
/// (button presses, charging) are replaced by one generic connect step.
List<GuideStep> preRecordingGuideSteps({required bool deadlift}) => [
      const GuideStep('Get Set Up in 30 Seconds',
          "Let's get you connected and ready to track your bar speed."),
      deadlift
          ? const GuideStep('Tracker Attachment (Deadlift)',
              'For deadlifts, strap the tracker on the inside of one of the plates, '
                  "sitting flat against the plate so it doesn't catch the floor on the "
                  'way down. Keep the straps tight and your grip clear of the device. '
                  'Keep it in the same spot every set for consistent results.')
          : const GuideStep('Tracker Attachment & Placement',
              'Strap on and position the tracker between the knuckles of the bar and '
                  'away from hands. Keep it in the same location for each exercise for '
                  'consistent results.'),
      const GuideStep('Connecting your Tracker',
          '1. Power on your sensor\n2. Tap the sensor status in the top bar to open '
              'Device, then connect to it\n\nNOTE: Allow Bluetooth access when asked.'),
    ];

/// Pages through [steps]; the last page's button says [doneLabel].
Future<void> showGuide(BuildContext context, List<GuideStep> steps,
        {String doneLabel = 'Done'}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _GuideDialog(steps: steps, doneLabel: doneLabel),
    );

class _GuideDialog extends StatefulWidget {
  const _GuideDialog({required this.steps, required this.doneLabel});

  final List<GuideStep> steps;
  final String doneLabel;

  @override
  State<_GuideDialog> createState() => _GuideDialogState();
}

class _GuideDialogState extends State<_GuideDialog> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_i];
    final last = _i == widget.steps.length - 1;
    return AlertDialog(
      key: const Key('guideDialog'),
      title: Text(step.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(step.body),
          const SizedBox(height: 12),
          Text('${_i + 1} / ${widget.steps.length}',
              style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
      actions: [
        if (_i > 0)
          TextButton(onPressed: () => setState(() => _i--), child: const Text('Back')),
        if (!last)
          TextButton(
              onPressed: () => Navigator.of(context).pop(), child: const Text('Skip')),
        FilledButton(
          key: const Key('guideNext'),
          onPressed: last
              ? () => Navigator.of(context).pop()
              : () => setState(() => _i++),
          child: Text(last ? widget.doneLabel : 'Next'),
        ),
      ],
    );
  }
}

Future<void> showGuideTip(BuildContext context, GuideTip tip) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('guideTip'),
        title: const Text(GuideTip.title),
        content: Text(tip.message),
        actions: [
          FilledButton(
              onPressed: () => Navigator.of(context).pop(), child: const Text('Got it')),
        ],
      ),
    );

/// Stance's `PreRecordingTips.poolFor`: general tips plus the exercise
/// family's. Its "Run STANCE with an internet connection" tip is left out:
/// analysis here runs on the phone.
List<String> preRecordingTipPool(ExerciseFamily family) => [
      'Press record just before your set and stop soon after. Long recording '
          'windows add noise to your data.',
      'Move with intent on every rep. The more honest the effort, the more '
          'accurate the data on your true output.',
      if (family == ExerciseFamily.bench) ...[
        'Pause for a second at lockout before you re-rack. It gives the sensor a '
            'clean end-point for your set.',
        'Re-rack the bar smoothly. A big or sudden movement to the rack can distort '
            'the data on your last rep.',
      ],
      if (family != ExerciseFamily.deadlift)
        "Don't spin or knock the bar while recording — natural rotation during reps "
            'is fine. The sensor picks up every movement, and extra spin or knocks '
            'can affect accuracy.',
      if (family == ExerciseFamily.deadlift) ...[
        'Clamp your plates tight to the collar. Rattling plates can throw off your '
            'bar speed reading.',
        'Pause briefly at the top of each rep and reset on the floor between reps. '
            'This helps the sensor read each rep separately.',
      ],
    ];
