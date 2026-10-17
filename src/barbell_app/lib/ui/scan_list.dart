import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../permissions/permission_service.dart';
import 'app_scope.dart';
import 'app_theme.dart';
import 'permission_prompts.dart';

/// BLE scan results as Stance's `DeviceScreen` list: a Bluetooth status row
/// and "Sensors" device rows (Stance's "Stance Tracker") with a Connect
/// pill. WitMotion sensors ("WT…") first, then by signal. Scans on open,
/// on pull-to-refresh and on [rescan]; reports the device whose Connect
/// was tapped.
class ScanList extends StatefulWidget {
  const ScanList({super.key, required this.onSelected, this.rescan});

  final ValueChanged<BluetoothDevice> onSelected;

  /// Scans again whenever this notifies (the Device page's refresh button).
  final Listenable? rescan;

  @override
  State<ScanList> createState() => _ScanListState();
}

class _ScanListState extends State<ScanList> {
  List<ScanResult> _results = [];
  bool _scanning = false;
  late final StreamSubscription<List<ScanResult>> _resultsSub;
  late final StreamSubscription<bool> _scanningSub;
  PermissionService? _permissions;
  bool _wasReady = false;

  @override
  void initState() {
    super.initState();
    widget.rescan?.addListener(_onRescan);
    _resultsSub = FlutterBluePlus.onScanResults.listen((r) {
      if (mounted) setState(() => _results = r);
    });
    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      if (mounted) setState(() => _scanning = s);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _permissions = AppScope.of(context).permissions;
      _wasReady = _permissions?.scanReady ?? true;
      _permissions?.addListener(_onPermissionsChanged);
      _scan();
    });
  }

  /// Start scanning as soon as Bluetooth becomes usable (e.g. after the
  /// user returns from Settings or turns the radio on).
  void _onPermissionsChanged() {
    setState(() {});
    final ready = _permissions!.scanReady;
    if (ready && !_wasReady && mounted) _startScan();
    _wasReady = ready;
  }

  void _onRescan() {
    if (!_scanning) _scan();
  }

  @override
  void dispose() {
    widget.rescan?.removeListener(_onRescan);
    _resultsSub.cancel();
    _scanningSub.cancel();
    _permissions?.removeListener(_onPermissionsChanged);
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  /// Check permission, radio and (Android 11 and older) Location Services,
  /// prompting if needed, then scan.
  Future<void> _scan() async {
    final p = _permissions;
    if (p != null) {
      if (!await ensureAccess(context, p, AppCapability.bluetooth)) return;
      if (!mounted || !await ensureLocationServices(context, p)) return;
    }
    await _startScan();
  }

  Future<void> _startScan() async {
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Scan failed: $e')));
      }
    }
  }

  static bool _isWitMotion(ScanResult r) =>
      r.device.platformName.startsWith('WT');

  @override
  Widget build(BuildContext context) {
    final named =
        _results.where((r) => r.device.platformName.isNotEmpty).toList()
          ..sort((a, b) {
            final wa = _isWitMotion(a), wb = _isWitMotion(b);
            if (wa != wb) return wa ? -1 : 1;
            return b.rssi.compareTo(a.rssi);
          });

    final (status, statusColor) = _bluetoothStatus();
    final text = Theme.of(context).textTheme;
    Widget section(String title) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: text.titleSmall?.copyWith(color: AppColors.subtitleGray),
      ),
    );

    return RefreshIndicator(
      onRefresh: _scan,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (_scanning) const LinearProgressIndicator(),
          section('Bluetooth'),
          // BluetoothStatusRow.
          DevicePanel(
            child: Row(
              children: [
                Expanded(
                  child: Text('Bluetooth Status', style: text.bodyLarge),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status,
                    style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          section('Sensors'),
          if (named.isEmpty && !_scanning)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'No sensors found. Pull down to scan again.',
                style: text.bodyMedium?.copyWith(
                  color: AppColors.subtitleGray,
                ),
              ),
            ),
          for (final r in named)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              // StanceTrackerDeviceRow, not connected: name + Connect pill.
              child: DevicePanel(
                minHeight: 52,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(r.device.platformName, style: text.bodyLarge),
                    ),
                    DevicePill(
                      text: 'Connect',
                      fill: _connectFill,
                      onTap: () async {
                        await FlutterBluePlus.stopScan();
                        widget.onSelected(r.device);
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Stance's adapter-state label and pill colour.
  (String, Color) _bluetoothStatus() {
    final p = _permissions;
    if (p != null && p.access(AppCapability.bluetooth) != Access.granted) {
      return ('Not authorized', AppColors.subtitleGray);
    }
    return switch (p?.radio) {
      RadioState.off => ('OFF', AppColors.disconnected),
      RadioState.unavailable => ('Unavailable', AppColors.subtitleGray),
      _ => ('ON', AppColors.connected),
    };
  }
}

/// Connect pill fill (Stance's enabled `StanceTrackerDeviceRow` pill).
const _connectFill = Color(0xFF5856D6);

/// A Stance card: white at 4 %, 16 dp radius, 16 x 14 dp padding.
class DevicePanel extends StatelessWidget {
  const DevicePanel({super.key, required this.child, this.minHeight = 0});

  final Widget child;
  final double minHeight;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: minHeight),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.cardFill,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

/// Stance's "Connect" pill: 999 dp radius, labelLarge semibold.
class DevicePill extends StatelessWidget {
  const DevicePill({
    super.key,
    required this.text,
    required this.fill,
    this.onTap,
  });

  final String text;
  final Color fill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: fill,
    shape: const StadiumBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}
