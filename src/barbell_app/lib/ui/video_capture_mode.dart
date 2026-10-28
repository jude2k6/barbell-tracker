import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../video/set_video_recorder.dart';
import '../video/video_settings.dart';
import 'app_theme.dart';

/// Stance's `SetVideoCaptureMode`: the full-screen camera shown after
/// "Start Set + Video". A 16 dp rounded preview inset 12 dp on black,
/// FPS / quality / lens pills bottom right, the record button bottom
/// centre (pulsing while recording) and a close button top right while
/// idle. The record button starts and stops the set itself.
class VideoCaptureMode extends StatelessWidget {
  const VideoCaptureMode({
    super.key,
    required this.recorder,
    required this.settings,
    required this.isRecording,
    required this.onRecordTap,
    required this.onClose,
    required this.onSettings,
  });

  final SetVideoRecorder recorder;
  final VideoSettings settings;
  final bool isRecording;

  /// Null disables the record button (sensor not streaming).
  final VoidCallback? onRecordTap;
  final VoidCallback onClose;
  final ValueChanged<VideoSettings> onSettings;

  @override
  Widget build(BuildContext context) {
    const fpsOptions = [30, 60];
    return ColoredBox(
      key: const Key('videoCapture'),
      color: Colors.black,
      child: Stack(children: [
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(children: [
                Positioned.fill(child: _Preview(recorder: recorder)),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    spacing: 8,
                    children: [
                      CameraControlPill<int>(
                        key: const Key('fpsPill'),
                        label: '${settings.fps} FPS',
                        enabled: !isRecording,
                        options: [for (final f in fpsOptions) (f, '$f FPS')],
                        onSelect: (f) => onSettings(settings.copyWith(fps: f)),
                      ),
                      CameraControlPill<VideoQuality>(
                        key: const Key('qualityPill'),
                        label: settings.quality.label,
                        enabled: !isRecording,
                        options: [for (final q in VideoQuality.values) (q, q.label)],
                        onSelect: (q) => onSettings(settings.copyWith(quality: q)),
                      ),
                      CameraControlPill<VideoLens>(
                        key: const Key('lensPill'),
                        label: settings.lens.label,
                        enabled: !isRecording,
                        options: [for (final l in VideoLens.values) (l, l.label)],
                        onSelect: (l) => onSettings(settings.copyWith(lens: l)),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 44),
            child: Stack(alignment: Alignment.center, children: [
              if (isRecording) const _PulseCircle(),
              _RecordButton(isRecording: isRecording, onTap: onRecordTap),
            ]),
          ),
        ),
        if (!isRecording)
          Align(
            alignment: Alignment.topRight,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Material(
                  color: const Color(0xFF232323),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const Key('closeCamera'),
                    onTap: onClose,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.close,
                          size: 20, color: Colors.white, semanticLabel: 'Close camera'),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// The camera preview filling its box (CameraX `PreviewView`'s default
/// fill-centre), or the camera error while it can't open.
class _Preview extends StatelessWidget {
  const _Preview({required this.recorder});

  final SetVideoRecorder recorder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: recorder,
        builder: (context, _) {
          final c = recorder.controller;
          final size = c?.value.previewSize;
          if (c != null && recorder.isReady && size != null) {
            return FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              // Preview size is landscape; phones record portrait.
              child: SizedBox(
                  width: size.height, height: size.width, child: CameraPreview(c)),
            );
          }
          if (recorder.error case final e?) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Camera: $e',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.subtitleGray)),
              ),
            );
          }
          return const SizedBox.expand();
        },
      );
}

/// Stance's `CameraControlPill`: the current value on a stadium at 8 %
/// white (12 x 6 dp padding, semi-bold labelMedium); tap for a menu of
/// [options].
class CameraControlPill<T> extends StatelessWidget {
  const CameraControlPill({
    super.key,
    required this.label,
    required this.enabled,
    required this.options,
    required this.onSelect,
  });

  final String label;
  final bool enabled;
  final List<(T, String)> options;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        enabled: enabled,
        tooltip: '',
        onSelected: onSelect,
        itemBuilder: (context) => [
          for (final (value, text) in options)
            PopupMenuItem(value: value, child: Text(text)),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: const ShapeDecoration(
              color: Color(0x14FFFFFF), shape: StadiumBorder()),
          child: Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      );
}

/// Stance's `RecordButton`: a 66 dp ring with a 4 dp white border around a
/// 60 dp red circle that morphs into a 32 dp primary rounded square while
/// recording.
class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.isRecording, required this.onTap});

  final bool isRecording;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final inner = isRecording ? 32.0 : 60.0;
    return Semantics(
      button: true,
      label: isRecording ? 'Stop' : 'Start Set',
      child: GestureDetector(
        key: const Key('captureRecord'),
        onTap: onTap,
        child: Container(
          width: 66,
          height: 66,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            width: inner,
            height: inner,
            decoration: BoxDecoration(
              color: isRecording ? AppColors.primary : const Color(0xFFFF0000),
              borderRadius: BorderRadius.circular(isRecording ? 6 : 30),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stance's `PulseCircle`: a 100 dp red (60 %) circle scaling 0.7 → 1.4
/// while fading 0.5 → 0 every 1.2 s.
class _PulseCircle extends StatefulWidget {
  const _PulseCircle();

  @override
  State<_PulseCircle> createState() => _PulseCircleState();
}

class _PulseCircleState extends State<_PulseCircle>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();
  late final _t = CurvedAnimation(parent: _controller, curve: Curves.fastOutSlowIn);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        builder: (context, child) => Opacity(
          opacity: 0.5 * (1 - _t.value),
          child: Transform.scale(scale: 0.7 + 0.7 * _t.value, child: child),
        ),
        child: Container(
          width: 100,
          height: 100,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Color(0x99FF0000)),
        ),
      );
}
