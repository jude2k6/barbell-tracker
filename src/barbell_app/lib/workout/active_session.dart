import 'session.dart';

/// When a session's last set ended: its end stamp, else its newest set's
/// end, else its start.
DateTime sessionEnd(Session s) =>
    s.endedAt ??
    s.sets.map((set) => set.endedAt).fold<DateTime?>(
        null, (a, b) => a == null || b.isAfter(a) ? b : a) ??
    s.startedAt;

/// Stance's `ActiveSessionPolicy`: the id of [exerciseId]'s newest session
/// if it ended on [now]'s local day and less than an hour before [now],
/// else null. Stance has no "finish session"; this is what makes a session
/// continuable.
String? activeSessionId(List<Session> sessions, String exerciseId,
    {DateTime? now}) {
  Session? newest;
  for (final s in sessions) {
    if (s.exerciseId != exerciseId) continue;
    if (newest == null || sessionEnd(s).isAfter(sessionEnd(newest))) newest = s;
  }
  if (newest == null) return null;
  final t = (now ?? DateTime.now()).toLocal();
  final end = sessionEnd(newest).toLocal();
  final sameDay = end.year == t.year && end.month == t.month && end.day == t.day;
  // Duration.toHours() truncates, as Stance's `Duration.between(...).toHours() < 1`.
  return sameDay && t.difference(end).inHours < 1 ? newest.id : null;
}
