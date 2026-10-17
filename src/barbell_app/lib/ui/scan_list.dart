import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../permissions/permission_service.dart';
import 'app_scope.dart';
import 'permission_prompts.dart';

/// BLE scan results, WitMotion sensors ("WT…") first, then by signal.
/// Scans on open and on pull-to-refresh; reports the tapped device.
class ScanList extends StatefulWidget {
  const ScanList({super.key, required this.onSelected});

  final ValueChanged<BluetoothDevice> onSelected;

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
    final ready = _permissions!.scanReady;
    if (ready && !_wasReady && mounted) _startScan();
    _wasReady = ready;
  }

  @override
  void dispose() {
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
    final named = _results
        .where((r) => r.device.platformName.isNotEmpty)
        .toList()
      ..sort((a, b) {
        final wa = _isWitMotion(a), wb = _isWitMotion(b);
        if (wa != wb) return wa ? -1 : 1;
        return b.rssi.compareTo(a.rssi);
      });

    return RefreshIndicator(
      onRefresh: _scan,
      child: ListView(
        children: [
          if (_scanning) const LinearProgressIndicator(),
          ListTile(
            title: Text('Nearby sensors',
                style: Theme.of(context).textTheme.titleSmall),
            trailing: IconButton(
              tooltip: 'Scan again',
              icon: const Icon(Icons.refresh),
              onPressed: _scanning ? null : _scan,
            ),
          ),
          if (named.isEmpty && !_scanning)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No sensors found. Pull down to scan again.'),
            ),
          for (final r in named)
            ListTile(
              leading: Icon(_isWitMotion(r) ? Icons.sensors : Icons.bluetooth),
              title: Text(r.device.platformName),
              subtitle: Text('${r.device.remoteId.str}  ·  ${r.rssi} dBm'),
              onTap: () async {
                await FlutterBluePlus.stopScan();
                widget.onSelected(r.device);
              },
            ),
        ],
      ),
    );
  }
}
