/// Stance's session day types (notes §18): Primary to Quaternary, stored as
/// a `Day:<name>` session tag. Readiness and session comparison only use
/// earlier sessions of the same type.
enum SessionDayType {
  primary('Primary'),
  secondary('Secondary'),
  tertiary('Tertiary'),
  quaternary('Quaternary');

  const SessionDayType(this.displayName);
  final String displayName;

  String get wireTag => 'Day:$displayName';

  /// The first `Day:` tag that names a type (`SessionDayType.fromTagList`).
  static SessionDayType? fromTags(List<String> tags) {
    for (final t in tags) {
      if (!t.startsWith('Day:')) continue;
      final name = t.substring(4);
      for (final d in values) {
        if (d.displayName == name) return d;
      }
    }
    return null;
  }
}

/// Stance's `extractSessionType`: the first type name found inside any tag,
/// else "". Readiness and comparison match sessions on this.
String sessionTypeOf(List<String> tags) {
  for (final t in tags) {
    for (final d in SessionDayType.values) {
      if (t.contains(d.displayName)) return d.displayName;
    }
  }
  return '';
}

/// Stance's `SessionTagRules.hasSessionTypeTag`.
bool hasSessionTypeTag(List<String> tags) => sessionTypeOf(tags).isNotEmpty;

/// [tags] with its `Day:` tags replaced by [type]'s, or removed for null
/// (Stance's `updateDayType`).
List<String> withDayType(List<String> tags, SessionDayType? type) => [
      for (final t in tags)
        if (!t.startsWith('Day:')) t,
      if (type != null) type.wireTag,
    ];

// Stance's tag editor (`SessionTagEditorSheet`, `SessionTagRules`), the
// Sessions card pills (`SessionTagFormatter`) and readiness's session label
// (`HistoricalDataRepositoryImpl.generateSessionLabel`). Tags are
// `<Section>:<value>` strings.

/// The editor's sections in Stance's order. Block and Week start with
/// [editorPageSize] numbered tags and grow by that many per "more…".
const editorPageSize = 6;
const editorExternalsCount = 5;

List<String> blockTags(int count) => [for (var i = 1; i <= count; i++) 'Block:$i'];
List<String> weekTags(int count) => [for (var i = 1; i <= count; i++) 'Week:$i'];
List<String> get dayTags => [for (final d in SessionDayType.values) d.wireTag];
List<String> get externalTags =>
    [for (var i = 1; i <= editorExternalsCount; i++) 'Externals:$i'];

/// Text before the first `:`, or the whole tag (`SessionTagRules.tagPrefix`).
String tagPrefix(String tag) {
  final i = tag.indexOf(':');
  return i <= 0 ? tag : tag.substring(0, i);
}

/// Deselects [tag] if present, else selects it in place of any tag of the
/// same section (`SessionTagRules.toggleTag`): one tag per section.
List<String> toggleTag(List<String> tags, String tag) {
  if (tags.contains(tag)) return [for (final t in tags) if (t != tag) t];
  final prefix = tagPrefix(tag);
  return [
    for (final t in tags)
      if (tagPrefix(t) != prefix) t,
    tag,
  ];
}

/// How many numbered tags the editor first shows for a section: Stance's
/// [editorPageSize], or more pages if a selected tag lies beyond it (own
/// addition, so a selected tag is never hidden).
int initialEditorCount(List<String> tags, String section) {
  var count = editorPageSize;
  for (final t in tags) {
    if (tagPrefix(t) != section) continue;
    final n = int.tryParse(t.substring(section.length + 1));
    while (n != null && n > count) {
      count += editorPageSize;
    }
  }
  return count;
}

const _displayOrder = ['Day', 'Week', 'Block', 'External', 'Externals'];

/// The pills on a Sessions card (`SessionTagFormatter.toDisplayTags`):
/// `//` tags hidden, sorted Day, Week, Block, Externals, then the rest, each
/// shortened. Stance breaks ties by tag creation date; tags here are kept
/// in the order they were added, so the sort is stable instead.
List<String> displayTags(List<String> tags) {
  int rank(String t) {
    final i = _displayOrder.indexOf(t.split(':').first);
    return i < 0 ? _displayOrder.length : i;
  }

  final visible = [
    for (final t in tags)
      if (!t.startsWith('//')) t,
  ];
  final indexed = visible.indexed.toList()
    ..sort((a, b) {
      final c = rank(a.$2).compareTo(rank(b.$2));
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final (_, t) in indexed) shortenTagText(t)];
}

/// `SessionTagFormatter.shortenTagText`: `Day:Primary` → `Primary`,
/// `Block:2` → `B:2`, `Week:3` → `W:3`, `Externals:1` → `E:1`.
String shortenTagText(String tag) {
  final parts = tag.split(':');
  final head = parts.first;
  final rest = parts.skip(1).join(':');
  if (head == 'Day' && parts.length > 1) return rest;
  final short = switch (head) {
    'Block' => 'B',
    'Week' => 'W',
    'Day' => 'D',
    'External' || 'Externals' => 'E',
    _ => head,
  };
  return parts.length > 1 ? '$short:$rest' : short;
}

/// Readiness history label (`generateSessionLabel`): the first tag starting
/// with "B" and the first starting with "W", joined by a space, e.g.
/// `Block:2 Week:3`; "" without either.
String readinessSessionLabel(List<String> tags) {
  final block = tags.where((t) => t.startsWith('B')).firstOrNull ?? '';
  final week = tags.where((t) => t.startsWith('W')).firstOrNull ?? '';
  return [block, week].where((s) => s.isNotEmpty).join(' ');
}
