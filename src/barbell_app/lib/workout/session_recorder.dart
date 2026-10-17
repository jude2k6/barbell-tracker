import '../analysis/exercises.dart';
import 'ids.dart';
import 'session.dart';
import 'session_store.dart';

/// Adds sets to one session: a new one, or [existing] when continuing.
/// Saves after every set so nothing is lost if the app dies. Nothing is
/// written until the first set is added.
///
/// There is no "finish": as in Stance, a session's end is its last set's
/// end, and it stays continuable while `activeSessionId` says so.
class SessionRecorder {
  SessionRecorder({
    required this.store,
    required Exercise exercise,
    Session? existing,
  }) : _session = existing ??
            Session(
              id: newId(),
              exerciseId: exercise.id,
              startedAt: DateTime.now(),
            );

  final SessionStore store;
  Session _session;

  Session get session => _session;

  /// Appends [set] to the latest saved copy of the session (sets may have
  /// been edited since it was opened), stamps the end and saves.
  Future<Session> addSet(SetRecord set) async {
    final latest = await store.load(_session.id) ?? _session;
    _session = latest.copyWith(sets: [...latest.sets, set], endedAt: set.endedAt);
    await store.save(_session);
    await store.setLastWeight(
        _session.exerciseId, LastWeight(set.weight, set.unit));
    return _session;
  }
}
