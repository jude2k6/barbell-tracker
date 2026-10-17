import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../video/overlay_timeline.dart';
import '../video/set_video_export_rules.dart';
import '../video/set_video_exporter.dart';
import '../workout/session.dart';
import 'charts/sticking_bar.dart';
import 'charts/velocity_chart.dart';
import 'format.dart';

/// Plays a set's video with a synced metrics panel, the velocity trace with
/// a playhead, per-rep jump chips, and a sync nudge that can be saved.
///
/// Share (top bar) and More → "Save to camera roll" export the clip cropped
/// to the reps with the overlay burned in, as the reference app's video
/// player sheet does (`FeedbackVideoPlayerSheet`).
class VideoReviewPage extends StatefulWidget {
  const VideoReviewPage({
    super.key,
    required this.set,
    required this.video,
    required this.title,
    this.onSaveOffset,
  });

  final SetRecord set;
  final File video;
  final String title;

  /// Persist a corrected sync offset. Null hides the Save button.
  final Future<void> Function(double offsetSec)? onSaveOffset;

  @override
  State<VideoReviewPage> createState() => _VideoReviewPageState();
}

class _VideoReviewPageState extends State<VideoReviewPage> {
  late final VideoPlayerController _player = VideoPlayerController.file(
    widget.video,
  );
  late double _offset = widget.set.videoOffsetSec ?? 0;
  late final double _savedOffset = _offset;
  String? _error;
  final _exporter = SetVideoExporter();

  /// Export running for Share or Save; the video is covered meanwhile.
  bool _preparing = false;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onTick);
    _player
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = '$e');
        });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // The reference app cancels the export when the player is dismissed.
    if (_preparing) _exporter.cancel();
    _player.removeListener(_onTick);
    _player.dispose();
    super.dispose();
  }

  OverlayTimeline get _timeline =>
      OverlayTimeline(widget.set, offsetSec: _offset);

  void _nudge(double delta) => setState(() => _offset += delta);

  /// What the export draws: the set as shown, including an unsaved nudge.
  SetVideoOverlayInput get _exportInput => SetVideoOverlayInput.fromSet(
    widget.set.copyWith(videoOffsetSec: _offset),
    videoPath: widget.video.path,
    weightLabel: fmtWeight(widget.set.weight, widget.set.unit),
  );

  /// Pause while exporting (the reference app frees its player), run
  /// [job], then resume if it was playing.
  Future<T> _withExport<T>(Future<T> Function() job) async {
    final wasPlaying = _player.value.isPlaying;
    await _player.pause();
    setState(() => _preparing = true);
    try {
      return await job();
    } finally {
      if (mounted) {
        setState(() => _preparing = false);
        if (wasPlaying) await _player.play();
      }
    }
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _share() async {
    final ok = await _withExport(() => _exporter.share(_exportInput));
    if (mounted && !ok) _toast('Could not prepare video');
  }

  Future<void> _saveToGallery() async {
    final ok = await _withExport(() => _exporter.saveToGallery(_exportInput));
    if (mounted) _toast(ok ? 'Saved to gallery' : 'Could not save video');
  }

  Future<void> _save() async {
    await widget.onSaveOffset?.call(_offset);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Sync saved')));
    Navigator.of(context).pop(_offset);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _player.value.isInitialized;
    final pos = _player.value.position;
    final dur = _player.value.duration;
    final frame = _timeline.at(pos);
    final set = widget.set;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.onSaveOffset != null && _offset != _savedOffset)
            TextButton(onPressed: _save, child: const Text('Save sync')),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _preparing || _error != null ? null : _share,
          ),
          PopupMenuButton<void>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert, color: Colors.white),
            enabled: _error == null,
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: _saveToGallery,
                child: const Text('Save to camera roll'),
              ),
            ],
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not play video: $_error'),
              ),
            )
          : ListView(
              children: [
                // Stance's `FeedbackVideoPlayerSheet`: 16 dp side padding,
                // the video clipped to a 30 dp radius at its aspect ratio.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: AspectRatio(
                      aspectRatio: ready
                          ? _player.value.aspectRatio.clamp(0.3, 3.0)
                          : 9 / 16,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (ready)
                            VideoPlayer(_player)
                          else
                            const ColoredBox(color: Colors.black),
                          if (!ready)
                            const Center(child: CircularProgressIndicator()),
                          Positioned(
                            left: 12,
                            bottom: 12,
                            child: _MetricsPanel(set: set, frame: frame),
                          ),
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () => _player.value.isPlaying
                                  ? _player.pause()
                                  : _player.play(),
                            ),
                          ),
                          if (_preparing) const _PreparingScrim(),
                        ],
                      ),
                    ),
                  ),
                ),
                if (ready)
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _player.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        onPressed: () => _player.value.isPlaying
                            ? _player.pause()
                            : _player.play(),
                      ),
                      Expanded(
                        child: Slider(
                          value: pos.inMilliseconds
                              .clamp(0, dur.inMilliseconds)
                              .toDouble(),
                          max: dur.inMilliseconds.toDouble().clamp(
                            1,
                            double.infinity,
                          ),
                          onChanged: (v) =>
                              _player.seekTo(Duration(milliseconds: v.round())),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          fmtElapsed(pos),
                          style: theme.textTheme.bodySmall.tabular,
                        ),
                      ),
                    ],
                  ),
                if (set.reps.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        for (final r in set.reps)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                'Rep ${r.index} · ${fmtVelocity(r.meanVelocity)}',
                              ),
                              selected: frame.headline?.index == r.index,
                              onSelected: (_) async {
                                await _player.seekTo(_timeline.seekTarget(r));
                                await _player.play();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                if (set.velocityTrace.length > 1 && set.traceHz != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: SizedBox(
                      height: 140,
                      child: CustomPaint(
                        painter: VelocityChartPainter(
                          velocity: set.velocityTrace,
                          hz: set.traceHz!,
                          reps: [
                            for (final r in set.reps)
                              RepWindow(r.index, r.startSec, r.endSec),
                          ],
                          lineColor: theme.colorScheme.primary,
                          shadeColor: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          gridColor: theme.colorScheme.outlineVariant,
                          labelStyle: theme.textTheme.labelSmall!,
                          playheadSec: frame.sensorSec,
                          playheadColor: theme.colorScheme.error,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Sync ${_offset >= 0 ? '+' : ''}${_offset.toStringAsFixed(2)} s\n'
                          'Nudge if the overlay leads or lags the bar.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      IconButton.outlined(
                        tooltip: 'Overlay earlier',
                        icon: const Icon(Icons.fast_rewind),
                        onPressed: () => _nudge(0.05),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Overlay later',
                        icon: const Icon(Icons.fast_forward),
                        onPressed: () => _nudge(-0.05),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Covers the video while an export runs: spinner and "Preparing video…".
class _PreparingScrim extends StatelessWidget {
  const _PreparingScrim();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black.withValues(alpha: 0.6),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 12),
          Text(
            'Preparing video…',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

/// Bottom-left panel, like the reference app's `SetMetricsOverlay`: rep
/// count, the headline rep's mean velocity, live velocity, and its
/// sticking band.
class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.set, required this.frame});

  final SetRecord set;
  final OverlayFrame frame;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const fg = Colors.white;
    final rep = frame.headline;
    final big = theme.textTheme.headlineMedium?.copyWith(color: fg).tabular;
    final small = theme.textTheme.bodySmall
        ?.copyWith(color: fg.withValues(alpha: 0.85))
        .tabular;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${fmtWeight(set.weight, set.unit)} · '
                'rep ${frame.repsDone}/${set.reps.length}',
                style: small,
              ),
              Text(
                rep == null ? '– m/s' : '${fmtVelocity(rep.meanVelocity)} m/s',
                style: big?.copyWith(
                  color: frame.activeRep != null ? stickingOrange : fg,
                ),
              ),
              if (frame.velocity != null)
                Text('now ${fmtVelocity(frame.velocity)} m/s', style: small),
              if (rep?.sticking != null) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: 180,
                  child: StickingBar(sticking: rep!.sticking!, height: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
