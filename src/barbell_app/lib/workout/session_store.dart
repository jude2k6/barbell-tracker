import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'session.dart';

/// Resolves the directory a store keeps its files under.
typedef BaseDirectory = Future<Directory> Function();

/// Sessions as JSON files under `<base>/sessions/<id>.json`, plus the last
/// weight used per exercise in `<base>/last_weights.json`.
///
/// Listeners are notified after every save or delete, so lists can reload.
class SessionStore extends ChangeNotifier {
  SessionStore({BaseDirectory? baseDirectory})
      : _base = baseDirectory ?? getApplicationDocumentsDirectory;

  final BaseDirectory _base;

  Future<Directory> _sessionsDir() async {
    final base = await _base();
    return Directory('${base.path}/sessions').create(recursive: true);
  }

  Future<File> _sessionFile(String id) async =>
      File('${(await _sessionsDir()).path}/$id.json');

  Future<void> save(Session session) async {
    final file = await _sessionFile(session.id);
    // Write-then-rename so a crash never leaves a half-written session.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(session.toJson()), flush: true);
    await tmp.rename(file.path);
    notifyListeners();
  }

  Future<Session?> load(String id) async {
    final file = await _sessionFile(id);
    if (!await file.exists()) return null;
    return _parse(file);
  }

  /// All readable sessions, newest first. Unreadable files are skipped.
  Future<List<Session>> list() async {
    final dir = await _sessionsDir();
    final sessions = <Session>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      final s = await _parse(f);
      if (s != null) sessions.add(s);
    }
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sessions;
  }

  /// Deletes the session file. Raw CSV recordings are kept.
  Future<void> delete(String id) async {
    final file = await _sessionFile(id);
    if (await file.exists()) await file.delete();
    notifyListeners();
  }

  Future<Session?> _parse(File f) async {
    try {
      final json = jsonDecode(await f.readAsString());
      return Session.fromJson(json as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Skipping unreadable session ${f.path}: $e');
      return null;
    }
  }

  // --- last weight per exercise ---

  Future<File> _weightsFile() async =>
      File('${(await _base()).path}/last_weights.json');

  Future<Map<String, dynamic>> _readWeights() async {
    try {
      final f = await _weightsFile();
      if (!await f.exists()) return {};
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<LastWeight?> lastWeight(String exerciseId) async {
    final entry = (await _readWeights())[exerciseId];
    if (entry is! Map<String, dynamic>) return null;
    final weight = (entry['weight'] as num?)?.toDouble();
    if (weight == null) return null;
    return LastWeight(weight, WeightUnit.fromName(entry['unit'] as String?));
  }

  Future<void> setLastWeight(String exerciseId, LastWeight w) async {
    final all = await _readWeights();
    all[exerciseId] = {'weight': w.weight, 'unit': w.unit.name};
    final f = await _weightsFile();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(all));
  }
}

/// The weight last used for an exercise, used to prefill the set screen.
class LastWeight {
  const LastWeight(this.weight, this.unit);
  final double weight;
  final WeightUnit unit;
}
