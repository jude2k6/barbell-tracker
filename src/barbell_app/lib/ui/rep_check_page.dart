import 'dart:async';

import 'package:flutter/material.dart';

import '../workout/preferences.dart';
import '../workout/rep_editing.dart';
import '../workout/session.dart';
import 'charts/velocity_chart.dart';
import 'format.dart';
import 'guides.dart';

/// Stance's Rep Check (notes §17): the set's reps as markers on its
/// velocity trace. Drag a rep's start and end, delete a rep, or add one by
/// setting a start and end time with the scrubber. Adds and deletes are
/// saved at once through [onCommit]; moved markers on Save.
class RepCheckPage extends StatefulWidget {
  const RepCheckPage({
    super.key,
    required this.set,
    required this.onCommit,
    this.preferences,
  });

  final SetRecord set;

  /// Saves the set rebuilt from these markers; returns it, or null when
  /// the markers were rejected.
  final Future<SetRecord?> Function(List<RepMarker> markers) onCommit;

  /// Remembers that the rep edit guide was seen; null never auto-shows it.
  final PreferencesStore? preferences;

  @override
  State<RepCheckPage> createState() => _RepCheckPageState();
}

class _RepCheckPageState extends State<RepCheckPage> {
  late SetRecord _set = widget.set;
  late List<RepMarker> _markers = markersOf(widget.set);
  bool _dirty = false;
  bool _saving = false;
  late double _scrub = 0;
  double? _addStart, _addEnd;
  Timer? _guideTimer;

  double get _duration => traceDurationSec(_set);

  @override
  void initState() {
    super.initState();
    final prefs = widget.preferences;
    if (prefs != null && canEditReps(_set) && !prefs.hasSeen(Guide.repEditGuide)) {
      // Stance's REP_EDIT_GUIDE_DELAY_MS.
      _guideTimer = Timer(const Duration(seconds: 1), () {
        if (!mounted) return;
        prefs.markSeen(Guide.repEditGuide);
        showGuide(context, repEditGuideSteps);
      });
    }
  }

  @override
  void dispose() {
    _guideTimer?.cancel();
    super.dispose();
  }

  Future<void> _commit(List<RepMarker> markers) async {
    setState(() => _saving = true);
    final saved = await widget.onCommit(markers);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved != null) {
        _set = saved;
        _markers = markersOf(saved);
        _dirty = false;
        _addStart = _addEnd = null;
      }
    });
    if (saved == null) await _error('Velocity data may not be available for this set.');
  }

  Future<void> _error(String message) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );

  Future<void> _delete(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rep'),
        content: Text('Are you sure you want to delete Rep ${i + 1}? '
            'This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('confirmDeleteRep'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await _commit([..._markers]..removeAt(i));
  }

  void _setStart() {
    final err = validateAddTime(_markers, _scrub, isStart: true);
    if (err != null) {
      _error(addTimeErrorText(err));
      return;
    }
    setState(() {
      _addStart = _scrub;
      _addEnd = null;
    });
  }

  void _setEnd() {
    final err = validateAddTime(_markers, _scrub, isStart: false, start: _addStart);
    if (err != null) {
      _error(addTimeErrorText(err));
      return;
    }
    setState(() => _addEnd = _scrub);
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes to rep markers. Do you want '
            'to save them before closing?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Discard')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (save == null) return false;
    if (save) await _commit(_markers);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editable = canEditReps(_set);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rep Check'),
          actions: [
            IconButton(
              tooltip: 'Guide',
              icon: const Icon(Icons.help_outline),
              onPressed: () => showGuide(context, repEditGuideSteps),
            ),
            TextButton(
              key: const Key('saveMarkers'),
              onPressed: _dirty && !_saving ? () => _commit(_markers) : null,
              child: const Text('Save'),
            ),
          ],
        ),
        body: !editable
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('No velocity data available'),
                  SizedBox(height: 8),
                  Text('Velocity data is needed to check rep shapes. This data may '
                      'not be available for older sets.'),
                ]),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Check each rep against the velocity chart. Drag a marker to '
                    'adjust its start and end, or add and delete reps, then save '
                    'your changes.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  VelocityChart(
                    velocity: _set.velocityTrace,
                    hz: _set.traceHz!,
                    reps: [
                      for (final (i, m) in _markers.indexed)
                        RepWindow(i + 1, m.startSec, m.endSec),
                    ],
                  ),
                  if (_saving) const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  for (final (i, m) in _markers.indexed) _repRow(theme, i, m),
                  const Divider(height: 32),
                  Text('Add Rep', style: theme.textTheme.titleSmall),
                  Row(children: [
                    Expanded(
                      child: Slider(
                        key: const Key('scrubber'),
                        value: _scrub.clamp(0, _duration),
                        max: _duration,
                        onChanged: (v) => setState(() => _scrub = v),
                      ),
                    ),
                    Text('${_scrub.toStringAsFixed(2)} s',
                        style: theme.textTheme.bodyMedium.tabular),
                  ]),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    OutlinedButton(
                      key: const Key('setStart'),
                      onPressed: _setStart,
                      child: Text(_addStart == null
                          ? 'Set start time'
                          : 'Start: ${_addStart!.toStringAsFixed(2)} s'),
                    ),
                    OutlinedButton(
                      key: const Key('setEnd'),
                      onPressed: _addStart == null ? null : _setEnd,
                      child: Text(_addEnd == null
                          ? 'Set end time'
                          : 'End: ${_addEnd!.toStringAsFixed(2)} s'),
                    ),
                    FilledButton(
                      key: const Key('addRep'),
                      onPressed: _addStart != null && _addEnd != null && !_saving
                          ? () => _commit(
                              [..._markers, RepMarker(_addStart!, _addEnd!)])
                          : null,
                      child: const Text('Add Rep'),
                    ),
                  ]),
                ],
              ),
      ),
    );
  }

  Widget _repRow(ThemeData theme, int i, RepMarker m) {
    // A marker can move up to its neighbours, never across them.
    final lo = i == 0 ? 0.0 : _markers[i - 1].endSec;
    final hi = i == _markers.length - 1 ? _duration : _markers[i + 1].startSec;
    final rep = i < _set.reps.length ? _set.reps[i] : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('Rep ${i + 1}', style: theme.textTheme.titleSmall),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'R${i + 1}s ${m.startSec.toStringAsFixed(2)} s · '
            'R${i + 1}e ${m.endSec.toStringAsFixed(2)} s'
            '${rep == null || _dirty ? '' : ' · ${fmtVelocity(rep.meanVelocity)} m/s'}',
            style: theme.textTheme.bodySmall.tabular,
          ),
        ),
        IconButton(
          key: ValueKey('deleteRep-$i'),
          tooltip: 'Delete rep',
          icon: const Icon(Icons.delete_outline),
          onPressed: _saving ? null : () => _delete(i),
        ),
      ]),
      if (hi > lo)
        RangeSlider(
          key: ValueKey('repRange-$i'),
          values: RangeValues(m.startSec.clamp(lo, hi), m.endSec.clamp(lo, hi)),
          min: lo,
          max: hi,
          onChanged: (r) {
            if (r.end <= r.start) return;
            setState(() {
              _markers = [..._markers]..[i] = RepMarker(r.start, r.end);
              _dirty = true;
            });
          },
        ),
    ]);
  }
}
