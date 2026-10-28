import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../video/overlay_timeline.dart';
import '../workout/preferences.dart';
import '../workout/rep_editing.dart';
import '../workout/session.dart';
import 'app_theme.dart';
import 'app_widgets.dart';
import 'charts/rep_check_chart.dart';
import 'format.dart';
import 'guides.dart';

/// What the unsaved-changes dialog chose.
enum _LeaveChoice { save, discard }

/// Stance's Rep Check (`RepCheckSheet`, notes §17 and §28): the set's reps
/// as markers on its velocity trace, with the set's video above when it has
/// one. Drag a marker's R#s/R#e bubble to move it; drag across the chart to
/// scrub (the video follows). Delete a rep, or add one by scrubbing to its
/// start and end. Adds and deletes are saved at once through [onCommit];
/// moved markers on Save.
class RepCheckPage extends StatefulWidget {
  const RepCheckPage({
    super.key,
    required this.set,
    required this.onCommit,
    this.preferences,
    this.video,
  });

  final SetRecord set;

  /// Saves the set rebuilt from these markers; returns it, or null when
  /// the markers were rejected.
  final Future<SetRecord?> Function(List<RepMarker> markers) onCommit;

  /// Remembers that the rep edit guide was seen; null never auto-shows it.
  final PreferencesStore? preferences;

  /// The set's video file, shown synced to the scrubber; null hides it.
  final File? video;

  @override
  State<RepCheckPage> createState() => _RepCheckPageState();
}

class _RepCheckPageState extends State<RepCheckPage> {
  late SetRecord _set = widget.set;
  late List<RepMarker> _markers = markersOf(widget.set);
  bool _dirty = false;
  bool _saving = false;
  late double _windowStart, _scrub;
  bool _adding = false;
  double? _addStart, _addEnd;
  Timer? _guideTimer;

  double get _duration => traceDurationSec(_set);
  RepCheckRange get _range => RepCheckRange(_markers, _duration);

  @override
  void initState() {
    super.initState();
    _resetView();
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

  /// As Stance re-keys its view state on the saved markers: the window
  /// centred on the reps and the scrubber in its middle.
  void _resetView() {
    final range = _range;
    _windowStart = range.initialWindowStart(markersOf(_set));
    final (lo, hi) = range.visible(_windowStart);
    _scrub = (lo + hi) / 2;
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
        _adding = false;
        _addStart = _addEnd = null;
        _resetView();
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
    if (ok != true) return;
    final rest = [..._markers]..removeAt(i);
    await _commit(rest);
    // Stance closes Rep Check once the last rep is deleted.
    if (rest.isEmpty && mounted && !_dirty) Navigator.of(context).pop();
  }

  void _scrubTo(double t) {
    final r = _range.scrub(t, _windowStart);
    setState(() {
      _scrub = r.scrub;
      _windowStart = r.windowStart;
    });
  }

  void _moveMarker(int i, bool isStart, double t) => setState(() {
        _markers = moveMarker(_markers, i,
            isStart: isStart, t: t, durationSec: _duration);
        _dirty = true;
      });

  /// Stance's `handleAddRepAction`: one button sets the start, then the
  /// end, then adds the rep, each at the scrubber.
  void _addRepAction() {
    if (_addStart == null) {
      final err = validateAddTime(_markers, _scrub, isStart: true);
      if (err != null) {
        _error(addTimeErrorText(err));
      } else {
        setState(() => _addStart = _scrub);
      }
    } else if (_addEnd == null) {
      final err =
          validateAddTime(_markers, _scrub, isStart: false, start: _addStart);
      if (err != null) {
        _error(addTimeErrorText(err));
      } else {
        setState(() => _addEnd = _scrub);
      }
    } else if (!_saving) {
      _commit([..._markers, RepMarker(_addStart!, _addEnd!)]);
    }
  }

  void _setAdding(bool adding) => setState(() {
        _adding = adding;
        _addStart = _addEnd = null;
      });

  /// Stance's unsaved-changes dialog: Save, Discard or Cancel. True when
  /// the page may close.
  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes to rep markers. Do you want '
            'to save them before closing?'),
        actions: [
          TextButton(
              key: const Key('unsavedSave'),
              onPressed: () => Navigator.pop(context, _LeaveChoice.save),
              child: const Text('Save')),
          TextButton(
              key: const Key('unsavedDiscard'),
              onPressed: () => Navigator.pop(context, _LeaveChoice.discard),
              child: const Text('Discard')),
          TextButton(
              key: const Key('unsavedCancel'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (choice == null) return false;
    if (choice == _LeaveChoice.save) await _commit(_markers);
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
        body: SafeArea(
          child: Stack(children: [
            Column(children: [
              _header(theme),
              Expanded(child: _content(theme, editable)),
            ]),
            if (_saving) Center(child: _savingOverlay(theme)),
          ]),
        ),
      ),
    );
  }

  /// Stance's sheet header: Save on the left, the title centred, Done on
  /// the right (Done leaves, asking about unsaved changes first).
  Widget _header(ThemeData theme) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Stack(alignment: Alignment.center, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AppSmallButton('Save',
                key: const Key('saveMarkers'),
                onPressed: _dirty && !_saving ? () => _commit(_markers) : null),
          ),
          Text('Rep Check',
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          Align(
            alignment: Alignment.centerRight,
            child: AppSmallButton('Done',
                secondary: true,
                onPressed: () => Navigator.of(context).maybePop()),
          ),
        ]),
      );

  /// Stance's "Saving changes…" card: black 80 %, spinner and text.
  Widget _savingOverlay(ThemeData theme) => Container(
        key: const Key('repCheckSaving'),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          Text('Saving changes…',
              style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _content(ThemeData theme, bool editable) {
    if (!editable) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('No velocity data available',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: AppColors.subtitleGray)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            child: Text(
                'Velocity data is needed to check rep shapes. This data may '
                'not be available for older sets.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.subtitleGray)),
          ),
        ]),
      );
    }
    final range = _range;
    final (lo, hi) = range.visible(_windowStart);
    final video = widget.video;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: CircleIconButton(
            icon: Icons.help_outline,
            tooltip: 'Guide',
            onPressed: () => showGuide(context, repEditGuideSteps),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Check each rep against the velocity chart. Drag a marker to '
            'adjust its start and end, or add and delete reps, then save '
            'your changes.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.subtitleGray),
          ),
        ),
        if (video != null) ...[
          const SizedBox(height: 8),
          RepCheckVideo(
            key: const Key('repCheckVideo'),
            file: video,
            timeline: OverlayTimeline(_set),
            scrubSec: _scrub,
          ),
        ],
        const SizedBox(height: 12),
        RepCheckChart(
          velocity: _set.velocityTrace,
          hz: _set.traceHz!,
          markers: _markers,
          original: markersOf(_set),
          windowStart: lo,
          windowEnd: hi,
          scrubSec: _scrub,
          onScrub: _scrubTo,
          adding: _adding,
          addStart: _addStart,
          addEnd: _addEnd,
          height: video != null ? 200 : 280,
        ),
        // The bubbles line up with the chart's plot, inside its 12 dp padding.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: RepMarkerBubbleRow(
            markers: _markers,
            windowStart: lo,
            windowEnd: hi,
            adding: _adding,
            onMoved: _moveMarker,
          ),
        ),
        if (range.scrolls) _windowSlider(range),
        if (_adding) _addRepPanel(theme) else ...[
          const SizedBox(height: 8),
          for (final (i, m) in _markers.indexed) ...[
            _repRow(theme, i, m),
            const SizedBox(height: 8),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: AppButton(
              key: const Key('addRep'),
              text: 'Add Rep',
              style: AppButtonStyle.secondary,
              onPressed: () => _setAdding(true),
            ),
          ),
        ],
      ],
    );
  }

  /// Stance pans a set longer than the 10 s window with a slider; moving
  /// it puts the scrubber in the window's middle unless a rep is being
  /// added.
  Widget _windowSlider(RepCheckRange range) => SliderTheme(
        data: SliderTheme.of(context).copyWith(
          thumbColor: AppColors.primary,
          activeTrackColor: AppColors.primary.withValues(alpha: 0.6),
          inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
        ),
        child: Slider(
          key: const Key('windowSlider'),
          value: _windowStart.clamp(range.dataStart, range.maxWindowStart),
          min: range.dataStart,
          max: range.maxWindowStart,
          onChanged: (v) => setState(() {
            _windowStart = v;
            if (!_adding) _scrub = v + repCheckBufferSec;
          }),
        ),
      );

  /// Stance's `AddRepPanel`: the chosen start and end, one button that
  /// sets the start, then the end, then adds the rep, and Cancel.
  Widget _addRepPanel(ThemeData theme) {
    Widget time(String label, double sec, Color color) => Row(children: [
          Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.subtitleGray)),
          const SizedBox(width: 8),
          Text(fmtRepCheckSec(sec),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w700)),
        ]);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_addStart != null)
          Row(children: [
            time('Start:', _addStart!, repStartColor),
            if (_addEnd != null) ...[
              const SizedBox(width: 8),
              time('End:', _addEnd!, repEndColor),
            ],
          ]),
        const SizedBox(height: 12),
        AppButton(
          key: const Key('addRepAction'),
          text: _addStart == null
              ? 'Set start time'
              : _addEnd == null
                  ? 'Set end time'
                  : 'Add Rep',
          onPressed: _saving ? null : _addRepAction,
        ),
        const SizedBox(height: 8),
        AppButton(
          key: const Key('cancelAddRep'),
          text: 'Cancel',
          style: AppButtonStyle.idle,
          onPressed: () => _setAdding(false),
        ),
      ]),
    );
  }

  /// Stance's `RepMarkerRow`: a card, "Rep N" semibold, the times in gray,
  /// and delete.
  Widget _repRow(ThemeData theme, int i, RepMarker m) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: appCard(),
        child: Row(children: [
          Text('Rep ${i + 1}',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            '${fmtRepCheckSec(m.startSec)} – ${fmtRepCheckSec(m.endSec)}',
            key: ValueKey('repTimes-$i'),
            style: theme.textTheme.bodyMedium.tabular
                ?.copyWith(color: AppColors.subtitleGray),
          ),
          IconButton(
            key: ValueKey('deleteRep-$i'),
            tooltip: 'Delete rep',
            icon: const Icon(Icons.delete_outline),
            onPressed: _saving ? null : () => _delete(i),
          ),
        ]),
      );
}

/// Stance's `RepCheckVideoPlayer`: the set's video, muted and paused,
/// 220 dp tall in a 12 dp rounded box, held at the frame under the
/// scrubber (the sync offset applied), with the scrubber time top-left.
class RepCheckVideo extends StatefulWidget {
  const RepCheckVideo({
    super.key,
    required this.file,
    required this.timeline,
    required this.scrubSec,
  });

  final File file;

  /// Maps the scrubber's sensor time to video time.
  final OverlayTimeline timeline;
  final double scrubSec;

  @override
  State<RepCheckVideo> createState() => _RepCheckVideoState();
}

class _RepCheckVideoState extends State<RepCheckVideo> {
  late final VideoPlayerController _player =
      VideoPlayerController.file(widget.file);
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _player.initialize().then((_) async {
      if (!mounted) return;
      await _player.setVolume(0);
      await _seek();
      if (mounted) setState(() => _ready = true);
    }).catchError((Object _) {
      // Unplayable: the box stays black, as an empty player.
    });
  }

  Future<void> _seek() =>
      _player.seekTo(widget.timeline.clampedVideoPosition(widget.scrubSec));

  @override
  void didUpdateWidget(RepCheckVideo old) {
    super.didUpdateWidget(old);
    if (_ready &&
        (old.scrubSec != widget.scrubSec ||
            old.timeline.offsetSec != widget.timeline.offsetSec)) {
      _seek();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 220,
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Colors.black),
          if (_ready)
            Center(
              child: AspectRatio(
                aspectRatio: _player.value.aspectRatio.clamp(0.3, 3.0),
                child: VideoPlayer(_player),
              ),
            ),
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(fmtRepCheckSec(widget.scrubSec),
                  key: const Key('repCheckVideoTime'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
