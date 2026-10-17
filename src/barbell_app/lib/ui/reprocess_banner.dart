import 'package:flutter/material.dart';

import '../workout/reprocess.dart';

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
    final scheme = theme.colorScheme;
    final onColor = scheme.onErrorContainer;
    return Card(
      key: const Key('reprocessBanner'),
      margin: EdgeInsets.zero,
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(state.message,
              key: const Key('reprocessMessage'),
              style: theme.textTheme.bodyMedium?.copyWith(color: onColor)),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail!,
                style: theme.textTheme.bodySmall?.copyWith(color: onColor)),
          ],
          if (state.showsButton) ...[
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('reprocessButton'),
              onPressed: state == ReprocessState.inProgress ? null : onReprocess,
              child: state == ReprocessState.inProgress
                  ? const Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Reprocessing…'),
                    ])
                  : const Text('Reprocess'),
            ),
          ],
        ]),
      ),
    );
  }
}
