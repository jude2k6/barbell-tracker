import 'package:flutter/material.dart';

import '../workout/session_tags.dart';

/// Stance's `SessionTagEditorSheet`: Block, Week, Day and Externals tags,
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Tags', style: theme.textTheme.titleLarge)),
          TextButton(
            key: const Key('tagEditorDone'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Add tags to compare what matters to you. '
            'Tap to select or deselect.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        _section('Block', blockTags(_blockCount),
            onMore: () => setState(() => _blockCount += editorPageSize)),
        _section('Week', weekTags(_weekCount),
            onMore: () => setState(() => _weekCount += editorPageSize)),
        _section('Day', dayTags),
        _section('Externals', externalTags),
      ]),
    );
  }

  Widget _section(String title, List<String> options, {VoidCallback? onMore}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            // Stance labels each chip with the raw tag, e.g. "Block:1".
            for (final tag in options)
              FilterChip(
                key: ValueKey('tag-$tag'),
                label: Text(tag),
                selected: _tags.contains(tag),
                showCheckmark: false,
                onSelected: (_) => _toggle(tag),
              ),
            if (onMore != null)
              ActionChip(
                key: ValueKey('tagMore-$title'),
                label: const Text('more…'),
                onPressed: onMore,
              ),
          ]),
        ]),
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
