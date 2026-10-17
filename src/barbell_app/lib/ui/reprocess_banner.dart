import 'package:flutter/material.dart';

import '../workout/reprocess.dart';
import 'comparison_views.dart';
import 'stance_theme.dart';

/// Stance's `ReprocessBanner` (notes §24), on the feedback page's set sheet
/// for a set that needs reprocessing: the message for [state], then
/// "Reprocess" (a spinner with "Reprocessing…" while it runs). There is no
/// button after "unavailable" or "still empty".
///
/// [detail] is the stored analysis error, if any (own addition, kept from
/// the earlier "Analysis failed" card).
class ReprocessBanner extends StatelessWidget {
  const ReprocessBanner({
    super.key,
    required this.state,
    required this.onReprocess,
    this.detail,
  });

  final ReprocessState state;
  final VoidCallback onReprocess;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Stance: #3A3A3C panel, 12 dp corners, 14/10 dp padding, the message
    // in bodySmall #E5C07B, then a 40 dp Primary button.
    final text = theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFE5C07B));
    return Container(
      key: const Key('reprocessBanner'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF3A3A3C), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(state.message, key: const Key('reprocessMessage'), style: text),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(detail!, style: text?.copyWith(color: StanceColors.subtitleGray)),
        ],
        if (state.showsButton) ...[
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('reprocessButton'),
            style: stanceButtonStyle(context).copyWith(
                // Stance keeps the Primary fill while it runs.
                backgroundColor: const WidgetStatePropertyAll(StanceColors.primary),
                foregroundColor: const WidgetStatePropertyAll(Colors.white)),
            onPressed: state == ReprocessState.inProgress ? null : onReprocess,
            child: state == ReprocessState.inProgress
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white)),
                    SizedBox(width: 10),
                    Text('Reprocessing…'),
                  ])
                : const Text('Reprocess'),
          ),
        ],
      ]),
    );
  }
}
