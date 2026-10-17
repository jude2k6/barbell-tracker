import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analysis/exercises.dart';
import '../analysis/imu_quality.dart';
import '../analysis/set_analysis.dart';
import '../permissions/permission_service.dart';
import '../recording/recording.dart';
import '../sensor/sensor_sample.dart';
import '../video/set_video_recorder.dart';
import '../video/video_settings.dart';
import '../workout/analysis_runner.dart';
import '../workout/file_log.dart';
import '../workout/ids.dart';
import '../workout/preferences.dart';
import '../workout/sensor_controller.dart';
import '../workout/session.dart';
import '../workout/session_recorder.dart';
import '../workout/set_log.dart';
import '../workout/signal_quality.dart';
import 'app_scope.dart';
import 'format.dart';
import 'guides.dart';
import 'live_trace.dart';
import 'permission_prompts.dart';
import 'sensor_status_chip.dart';
import 'stance_theme.dart';
import 'stance_widgets.dart';
import 'video_settings_sheet.dart';
import 'workout_flow.dart';

enum _Phase { idle, recording, analysing }

/// Stance's `PreRecordingRoute`: exercise, set type pill and weight, a tip,
/// then a full-width Start Set / Stop button with the seconds above it
/// while recording (plus our video card and live trace). After Stop the
/// set is analysed under
/// a 60 s countdown, saved to the session, and the session feedback page
/// opens; there is no separate per-set result page. The lifter may leave
/// while it analyses: the set is still saved. A setup guide shows on the
/// first visit and from the top bar.
class RecordSetPage extends StatefulWidget {
  const RecordSetPage({
    super.key,
    required this.exercise,
    required this.weight,
    required this.unit,
    required this.setType,
    this.session,
  });

  final Exercise exercise;
  final double weight;
  final WeightUnit unit;
  final SetType setType;

  /// Session to add to; null starts a new one.
  final Session? session;

  @override
  State<RecordSetPage> createState() => _RecordSetPageState();
}

class _RecordSetPageState extends State<RecordSetPage> {
  late final AppScope _app = AppScope.of(context);
  late final SessionRecorder _recorder = SessionRecorder(
      store: _app.sessions, exercise: widget.exercise, existing: widget.session);

  _Phase _phase = _Phase.idle;
  Recording? _recording;
  StreamSubscription<SensorSample>? _sampleSub;
  final _stopwatch = Stopwatch();
  Timer? _ticker;

  final _video = SetVideoRecorder();
  String? _pendingSetId;
  VideoSettings get _videoSettings =>
      _app.videoSettings?.value ?? const VideoSettings();

  bool get _cameraAllowed =>
      _app.permissions?.granted(AppCapability.camera) ?? true;

  /// Turning video on asks for the camera (and microphone if sound is on)
  /// first; without the microphone, video is recorded silently.
  Future<void> _setVideoEnabled(bool on) async {
    final store = _app.videoSettings!;
    final p = _app.permissions;
    if (!on) return store.update(_videoSettings.copyWith(enabled: false));
    if (p != null && !await ensureAccess(context, p, AppCapability.camera)) return;
    var settings = _videoSettings.copyWith(enabled: true);
    if (settings.audio && p != null && mounted &&
        !await ensureAccess(context, p, AppCapability.microphone)) {
      settings = settings.copyWith(audio: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No microphone access: recording video without sound.')));
      }
    }
    await store.update(settings);
  }

  @override
  void initState() {
    super.initState();
    // Warm the deadlift model cache so the first set's analysis isn't slowed.
    if (widget.exercise.isDeadlift) loadDeadliftModels();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final prefs = _app.preferences;
      if (prefs != null && !prefs.hasSeen(Guide.preRecordingGuide)) {
        prefs.markSeen(Guide.preRecordingGuide);
        _showSetupGuide();
      }
      _app.sensor.addListener(_onSensorChanged);
      _app.videoSettings?.addListener(_onVideoSettingsChanged);
      _app.permissions?.addListener(_onVideoSettingsChanged);
      _onVideoSettingsChanged();
    });
  }

  void _showSetupGuide() => showGuide(
      context, preRecordingGuideSteps(deadlift: widget.exercise.isDeadlift),
      doneLabel: 'Ready to Record');

  /// One random tip per visit, as Stance's `PreRecordingTips.select`.
  late final String _tip = () {
    final pool = preRecordingTipPool(widget.exercise.family);
    return pool[math.Random().nextInt(pool.length)];
  }();

  /// Stance's `ANALYSIS_COUNTDOWN_SECONDS`.
  static const _analysisCountdown = Duration(seconds: 60);
  final _analysisClock = Stopwatch();

  void _onVideoSettingsChanged() {
    if (!mounted || _phase != _Phase.idle) return;
    var settings = _videoSettings;
    // Microphone revoked since sound was turned on: record silently.
    if (settings.audio &&
        !(_app.permissions?.granted(AppCapability.microphone) ?? true)) {
      settings = settings.copyWith(audio: false);
    }
    if (settings.enabled && !_cameraAllowed) {
      _video.close(); // revoked in Settings: wait for access again
    } else if (settings.enabled) {
      _video.open(settings);
    } else {
      _video.close();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _app.sensor.removeListener(_onSensorChanged);
    _app.videoSettings?.removeListener(_onVideoSettingsChanged);
    _app.permissions?.removeListener(_onVideoSettingsChanged);
    _video.dispose();
    _ticker?.cancel();
    _sampleSub?.cancel();
    super.dispose();
  }

  /// Stop the set if the sensor drops mid-recording; keep what we have.
  void _onSensorChanged() {
    if (_phase == _Phase.recording && !_app.sensor.isStreaming) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sensor disconnected; recording stopped.')));
      _stop();
    }
  }

  Future<void> _start() async {
    _pendingSetId = newId();
    // Camera first: its start latency is longer and timestamped anyway.
    if (_videoSettings.enabled && _video.isReady) {
      try {
        await _video.start();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Video did not start: $e')));
        }
      }
    }
    if (!mounted) return;
    final sensor = _app.sensor;
    final recording = Recording(
      sensorName: sensor.link?.name ?? 'sensor',
      startedAt: DateTime.now(),
    );
    AppLog.i('RecordingRepository',
        'recording started set=$_pendingSetId exercise=${widget.exercise.id} sensor=${recording.sensorName}');
    _sampleSub = sensor.samples.listen(recording.samples.add);
    _stopwatch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = recording;
      _phase = _Phase.recording;
    });
  }

  Future<void> _stop() async {
    final recording = _recording;
    if (recording == null || _phase != _Phase.recording) return;
    await _sampleSub?.cancel();
    _sampleSub = null;
    _ticker?.cancel();
    _stopwatch.stop();
    HapticFeedback.mediumImpact();
    final endedAt = DateTime.now();
    final setId = _pendingSetId ?? newId();
    final clip = _video.isRecording ? await _video.stop(setId) : null;

    AppLog.i('RecordingRepository',
        'recording stopped set=$setId samples=${recording.samples.length}');
    if (recording.samples.isEmpty) {
      await clip?.file.delete().catchError((_) => clip.file);
      if (!mounted) return;
      setState(() {
        _recording = null;
        _phase = _Phase.idle;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No sensor data was recorded. Check your device '
                'connection and try again.')));
      }
      return;
    }

    // From here the set is saved even if the lifter leaves the page.
    _analysisClock
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() => _phase = _Phase.analysing);

    // Raw samples first, so they survive any analysis failure.
    String? rawPath;
    try {
      rawPath = _app.recordings.relativePath(await _app.recordings.save(recording));
    } catch (e) {
      AppLog.e('RecordingRepository', 'Saving raw recording failed', e);
    }

    SetAnalysis? analysis;
    String? error;
    try {
      analysis = await _app.analyzer(recording.samples, widget.exercise);
    } catch (e) {
      error = describeAnalysisError(e);
      AppLog.e('SetCompletion', 'analysis failed set=$setId', e);
    }
    if (analysis != null) {
      AppLog.i('SetCompletion',
          'analysis done set=$setId pipeline=${analysis.pipeline} reps=${analysis.reps.length}');
    }

    final (trace, traceHz) = analysis == null
        ? (const <double>[], null)
        : downsampleTrace(analysis.velocity, analysis.velocityHz);
    final originUs = analysis?.originHostTimeUs ?? recording.samples.first.hostTimeUs;
    final set = SetRecord(
      id: setId,
      startedAt: recording.startedAt,
      endedAt: endedAt,
      weight: widget.weight,
      unit: widget.unit,
      setType: widget.setType,
      reps: [
        for (final r in analysis?.reps ?? const <RepResult>[])
          RepRecord.fromResult(r),
      ],
      pipeline: analysis?.pipeline,
      warnings: analysis?.warnings ?? const [],
      measuredHz: analysis?.measuredHz,
      rawCsvFile: rawPath,
      sampleCount: recording.samples.length,
      analysisError: error,
      velocityTrace: trace,
      traceHz: traceHz,
      videoFile: clip == null ? null : SetVideoRecorder.relativePath(clip.file),
      videoOffsetSec:
          clip == null ? null : (originUs - clip.startHostTimeUs) / 1e6,
      imuQuality: computeImuQuality(recording.samples),
    );
    try {
      final session = await _recorder.addSet(set);
      logSetCompleted(set,
          exercise: widget.exercise,
          sessionId: session.id,
          sensorName: recording.sensorName);
      _ticker?.cancel();
      if (!mounted) return;
      showFeedbackAfterSet(context, session, continuing: widget.session != null);
    } catch (e) {
      _ticker?.cancel();
      AppLog.e('SetCompletion', 'Saving set failed', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save this set: $e')));
      setState(() {
        _recording = null;
        _phase = _Phase.idle;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sensor = _app.sensor;
    final idle = _phase == _Phase.idle;
    final gray = StanceColors.subtitleGray;

    return PopScope(
      canPop: _phase != _Phase.recording,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: ListenableBuilder(
              listenable: sensor,
              builder: (context, _) => CustomScrollView(slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WorkoutTopBar(
                        sensor: sensor,
                        enabled: idle,
                        trailing: _GuideHeaderButton(
                          key: const Key('setupGuide'),
                          label: 'Setup Guide',
                          onPressed: idle ? _showSetupGuide : null,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.exercise.rawValue,
                              style: theme.textTheme.bodyLarge?.copyWith(color: gray)),
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0x14FFFFFF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(widget.setType.displayName,
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(color: gray)),
                          ),
                          const SizedBox(height: 4),
                          Text(fmtWeight(widget.weight, widget.unit),
                              key: const Key('setSummary'),
                              style: theme.textTheme.displaySmall.tabular),
                        ],
                      ),
                      if (_app.videoSettings != null) ...[
                        const SizedBox(height: 16),
                        _VideoCard(
                          recorder: _video,
                          settings: _videoSettings,
                          enabled: idle,
                          cameraBlocked: _videoSettings.enabled && !_cameraAllowed,
                          onToggle: _setVideoEnabled,
                          onFixAccess: () => _setVideoEnabled(true),
                          onSettings: () => showVideoSettingsSheet(
                              context, _app.videoSettings!, _app.permissions),
                        ),
                      ],
                      const Spacer(),
                      Padding(
                        key: const Key('recordingTip'),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Column(children: [
                          Text('Tips', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(_tip,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(color: gray)),
                        ]),
                      ),
                      const Spacer(),
                      if (_phase == _Phase.analysing) ...[
                        _AnalysisCountdown(
                            elapsed: _analysisClock.elapsed, total: _analysisCountdown),
                        const SizedBox(height: 12),
                      ] else if (_phase == _Phase.recording) ...[
                        // Own addition: the live trace above Stance's
                        // progress bar and seconds.
                        LiveTrace(sensor: sensor, height: 120, color: StanceColors.error),
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        Row(children: [
                          Text('${_stopwatch.elapsed.inSeconds}s',
                              style: theme.textTheme.bodyMedium.tabular),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${_recording?.samples.length ?? 0} samples',
                                style: theme.textTheme.bodySmall.tabular
                                    ?.copyWith(color: gray)),
                          ),
                          // Stance's RecordingControlsRow badge.
                          if (assessRecentSignal(_recording?.samples ?? const [])
                              case final quality?)
                            SignalQualityBadge(quality: quality),
                        ]),
                        const SizedBox(height: 12),
                      ],
                      if (!sensor.isStreaming && idle) ...[
                        Text('Sensor not streaming. Connect your sensor to record.',
                            style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _StanceButton(
                            label: 'Device',
                            height: 50,
                            onPressed: () => openDevice(context),
                          ),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _StanceButton(
                          key: const Key('recordButton'),
                          label: switch (_phase) {
                            _Phase.idle => 'Start Set',
                            _Phase.recording => 'Stop',
                            _Phase.analysing => 'Please wait…',
                          },
                          height: 50,
                          onPressed: switch (_phase) {
                            _Phase.idle => sensor.isStreaming ? _start : null,
                            _Phase.recording => _stop,
                            _Phase.analysing => null,
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}


/// Record-video switch, settings, and a live preview while enabled.
class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.recorder,
    required this.settings,
    required this.enabled,
    required this.onToggle,
    required this.onSettings,
    this.cameraBlocked = false,
    this.onFixAccess,
  });

  final SetVideoRecorder recorder;
  final VideoSettings settings;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSettings;

  /// Video is on but camera access was revoked.
  final bool cameraBlocked;
  final VoidCallback? onFixAccess;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: recorder,
        builder: (context, _) {
          final c = recorder.controller;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SwitchListTile(
              key: const Key('videoSwitch'),
              secondary: Icon(recorder.isRecording ? Icons.videocam : Icons.videocam_outlined,
                  color: recorder.isRecording ? theme.colorScheme.error : null),
              title: const Text('Record video'),
              subtitle: Text('${settings.lens.label} · ${settings.quality.label} · '
                  '${settings.fps} fps${settings.audio ? ' · sound' : ''}'),
              value: settings.enabled,
              onChanged: enabled ? onToggle : null,
            ),
            if (cameraBlocked)
              ListTile(
                key: const Key('cameraBlocked'),
                leading: Icon(Icons.no_photography, color: theme.colorScheme.error),
                title: const Text('Camera access needed'),
                subtitle: const Text('Sets record without video until it is allowed.'),
                trailing: TextButton(onPressed: onFixAccess, child: const Text('Allow')),
              )
            else if (settings.enabled && recorder.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text('Camera: ${recorder.error}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              ),
            if (settings.enabled && c != null && recorder.isReady)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: Center(
                  child: AspectRatio(
                    // Preview size is landscape; phones record portrait.
                    aspectRatio: 1 / c.value.aspectRatio,
                    child: CameraPreview(c),
                  ),
                ),
              ),
            if (settings.enabled)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: enabled ? onSettings : null,
                  icon: const Icon(Icons.tune),
                  label: const Text('Video settings'),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

/// Stance's `AnalysisCountdownBar`: "Analysing your set" and the seconds
/// left over a 10 dp bar that fills over 60 s (indeterminate once
/// overdue), on a 16 dp rounded panel at white 8 %.
class _AnalysisCountdown extends StatelessWidget {
  const _AnalysisCountdown({required this.elapsed, required this.total});

  final Duration elapsed, total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final left = total - elapsed;
    final overdue = left <= Duration.zero;
    final note = theme.textTheme.labelMedium?.copyWith(color: StanceColors.subtitleGray);
    return Container(
      key: const Key('analysisCountdown'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('Analysing your set', style: theme.textTheme.bodyLarge)),
          Text(
              overdue
                  ? 'Taking longer than usual'
                  : '${(left.inMilliseconds / 1000).ceil()}s left',
              style: note.tabular),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            minHeight: 10,
            color: StanceColors.primary,
            backgroundColor: const Color(0x33FFFFFF),
            value: overdue ? null : elapsed.inMilliseconds / total.inMilliseconds,
          ),
        ),
        const SizedBox(height: 12),
        Text('You can leave this screen — your set will still be saved.', style: note),
      ]),
    );
  }
}

/// Stance's `SignalQualityBadge`: the rating in its colour over the
/// delivered packet rate, on a 15 % tint of that colour.
class SignalQualityBadge extends StatelessWidget {
  const SignalQualityBadge({super.key, required this.quality});

  final SignalQuality quality;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (quality.rating) {
      SignalRating.good => StanceColors.success,
      SignalRating.fair => StanceColors.amber,
      SignalRating.poor => StanceColors.error,
    };
    return Material(
      key: const Key('signalQualityBadge'),
      color: color.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(quality.rating.label,
              style: theme.textTheme.labelMedium?.copyWith(color: color)),
          Text(quality.rateLabel,
              style: theme.textTheme.labelSmall.tabular
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// Stance's `WorkoutTopBar`: a 44 dp row with the back button, then
/// [trailing] and the device status on the right. (The page supplies the
/// 18 dp side inset.)
class _WorkoutTopBar extends StatelessWidget {
  const _WorkoutTopBar(
      {required this.sensor, required this.enabled, required this.trailing});

  final SensorController sensor;

  /// Device status opens the device page only while idle.
  final bool enabled;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(children: [
        CircleIconButton(
          key: const Key('workoutBack'),
          icon: Icons.arrow_back,
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        trailing,
        const SizedBox(width: 8),
        SensorStatusChip(
            sensor: sensor, onPressed: enabled ? () => openDevice(context) : null),
      ]),
    );
  }
}

/// Stance's `GuideHeaderButton`: a 32 dp pill with a 2 dp pink-to-purple
/// (70 %) gradient outline, an icon and 14 sp semibold text; half opacity
/// while disabled. Stance's icon is its `stance_ai` vector drawable; a
/// Material sparkle stands in.
class _GuideHeaderButton extends StatelessWidget {
  const _GuideHeaderButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 32,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                  colors: [Color(0xB3F415C3), Color(0xB3792EFF)]),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: StanceColors.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.auto_awesome, size: 20, color: Color(0xFFF415C3)),
                const SizedBox(width: 4),
                Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stance's `StanceButton` (Primary, or Idle while disabled): white
/// bodyLarge semibold on the primary colour, 16 dp corners.
class _StanceButton extends StatelessWidget {
  const _StanceButton(
      {super.key, required this.label, required this.onPressed, this.height = 42});

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: Size.fromHeight(height),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: StanceColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0x0FFFFFFF),
        disabledForegroundColor: const Color(0xFF888888),
        textStyle: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
