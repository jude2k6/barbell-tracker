import 'package:flutter/widgets.dart';

import 'app_scope.dart';

/// Reconnects to the saved sensor when Home or the Device screen opens
/// (Stance's `onHomeScreenReadyForAutoConnect` / `onDeviceScreenReady`). If
/// Bluetooth isn't usable yet it tries again once it is; the attempt itself
/// happens once per app run (see `SavedSensor`).
class AutoReconnect extends StatefulWidget {
  const AutoReconnect({super.key, required this.child});

  final Widget child;

  @override
  State<AutoReconnect> createState() => _AutoReconnectState();
}

class _AutoReconnectState extends State<AutoReconnect> {
  Listenable? _permissions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _permissions?.removeListener(_try);
    _permissions = AppScope.of(context).permissions
      ?..addListener(_try);
    WidgetsBinding.instance.addPostFrameCallback((_) => _try());
  }

  void _try() {
    if (!mounted) return;
    final app = AppScope.of(context);
    app.savedSensor?.autoConnect(permitted: app.permissions?.scanReady ?? false);
  }

  @override
  void dispose() {
    _permissions?.removeListener(_try);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
