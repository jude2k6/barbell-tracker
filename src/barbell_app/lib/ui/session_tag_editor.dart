import 'package:flutter/material.dart';

import '../workout/session_tags.dart';
import 'stance_theme.dart';

const _sheetColor = Color(0xFF1C1C1E);

/// Stance's `SessionTagEditorSheet` (container 0xFF1C1C1E, 20 dp side
/// padding, 32 dp bottom): Block, Week, Day and Externals tags,
/// one per section. Done and dismissing both keep the edits (Stance's
/// dismiss handler also calls `onDone`). Returns the edited tags.
///
/// Stance ships this sheet and its save path (`applyTagsFromEditor`) but
/// nothing opens it; here the feedback page's "Edit session tags" does.
Future<List<String>> showSessionTagEditor(
    BuildContext context, List<String> initialTags) async {
  var edited = initialTags;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: _sheetColor,
    builder: (context) => SessionTagEditor(
      initialTags: initialTags,
      onChanged: (tags) => edited = tags,
    ),
  );
  return edited;
}

class SessionTagEditor extends StatefulWidget {
  const SessionTagEditor(
      {super.key, required this.initialTags, required this.onChanged});

  final List<String> initialTags;
  final ValueChanged<List<String>> onChanged;

  @override
  State<SessionTagEditor> createState() => _SessionTagEditorState();
}

class _SessionTagEditorState extends State<SessionTagEditor> {
  late List<String> _tags = widget.initialTags;
  late int _blockCount = initialEditorCount(_tags, 'Block');
  late int _weekCount = initialEditorCount(_tags, 'Week');

  void _toggle(String tag) {
    setState(() => _tags = toggleTag(_tags, tag));
    widget.onChanged(_tags);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tags', style: theme.textTheme.headlineSmall),
              TextButton(
                key: const Key('tagEditorDone'),
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Done'),
              ),
            ]),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Add tags to compare what matters to you. '
            'Tap to select or deselect.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: StanceColors.subtitleGray),
          ),
        ),
        _section('Block', blockTags(_blockCount),
            onMore: () => setState(() => _blockCount += editorPageSize)),
        const SizedBox(height: 16),
        _section('Week', weekTags(_weekCount),
            onMore: () => setState(() => _weekCount += editorPageSize)),
        const SizedBox(height: 16),
        _section('Day', dayTags),
        const SizedBox(height: 16),
        _section('Externals', externalTags),
      ]),
    );
  }

  /// Stance's `TagSection`: title, then a wrapping row of 8 dp pills.
  Widget _section(String title, List<String> options, {VoidCallback? onMore}) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        // Stance labels each chip with the raw tag, e.g. "Block:1".
        for (final tag in options)
          _pill(
            key: ValueKey('tag-$tag'),
            label: tag,
            fill: _tags.contains(tag)
                ? StanceColors.primary.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.08),
            color: Colors.white,
            onTap: () => _toggle(tag),
          ),
        if (onMore != null)
          _pill(
            key: ValueKey('tagMore-$title'),
            label: 'more…',
            fill: Colors.white.withValues(alpha: 0.12),
            color: StanceColors.subtitleGray,
            onTap: onMore,
          ),
      ]),
    ]);
  }

  Widget _pill({
    required Key key,
    required String label,
    required Color fill,
    required Color color,
    required VoidCallback onTap,
  }) =>
      Material(
        key: key,
        color: fill,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: color)),
          ),
        ),
      );
}

/// Stance's `SessionTagsRow` on a Sessions card: a tag icon, the tag count
/// and the shortened tags as pills, scrolling sideways. Nothing without
/// tags.
class SessionTagsRow extends StatelessWidget {
  const SessionTagsRow({super.key, required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final shown = displayTags(tags);
    if (shown.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(Icons.local_offer, size: 15, color: theme.colorScheme.outline),
        const SizedBox(width: 8),
        CircleAvatar(
          radius: 10,
          backgroundColor: theme.colorScheme.outline,
          child: Text('${shown.length}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.surface)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final t in shown)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Chip(
                    label: Text(t),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
