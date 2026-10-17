import 'package:flutter/material.dart';

import '../workout/session.dart';
import '../workout/session_store.dart';

/// Loads the session list and reloads whenever [store] changes.
class SessionsBuilder extends StatefulWidget {
  const SessionsBuilder({super.key, required this.store, required this.builder});

  final SessionStore store;
  final Widget Function(BuildContext context, List<Session>? sessions) builder;

  @override
  State<SessionsBuilder> createState() => _SessionsBuilderState();
}

class _SessionsBuilderState extends State<SessionsBuilder> {
  List<Session>? _sessions;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(SessionsBuilder old) {
    super.didUpdateWidget(old);
    if (old.store != widget.store) {
      old.store.removeListener(_reload);
      widget.store.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final sessions = await widget.store.list();
    if (mounted) setState(() => _sessions = sessions);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _sessions);
}
