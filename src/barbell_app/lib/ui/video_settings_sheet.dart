import 'package:flutter/material.dart';

import '../permissions/permission_service.dart';
import '../video/video_settings.dart';
import 'permission_prompts.dart';

/// Lens, quality, frame rate and sound for set videos.
Future<void> showVideoSettingsSheet(
  BuildContext context,
  VideoSettingsStore store, [
  PermissionService? permissions,
]) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ValueListenableBuilder<VideoSettings>(
        valueListenable: store,
        builder: (context, s, _) {
          final theme = Theme.of(context);
          Widget row<T>(
            String label,
            List<(T, String)> options,
            T selected,
            ValueChanged<T> onSelected,
          ) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              for (final (value, text) in options)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _Pill(
                    text: text,
                    selected: value == selected,
                    onTap: () => onSelected(value),
                  ),
                ),
            ]),
          );
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              row<VideoLens>(
                'Camera',
                [for (final l in VideoLens.values) (l, l.label)],
                s.lens,
                (v) => store.update(s.copyWith(lens: v)),
              ),
              row<VideoQuality>(
                'Quality',
                [for (final q in VideoQuality.values) (q, q.label)],
                s.quality,
                (v) => store.update(s.copyWith(quality: v)),
              ),
              row<int>(
                'Frame rate',
                const [(30, '30'), (60, '60')],
                s.fps,
                (v) => store.update(s.copyWith(fps: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Record sound'),
                subtitle: const Text('Needs microphone permission'),
                value: s.audio,
                onChanged: (v) async {
                  if (v &&
                      permissions != null &&
                      !await ensureAccess(context, permissions, AppCapability.microphone)) {
                    return;
                  }
                  await store.update(s.copyWith(audio: v));
                },
              ),
            ]),
          );
        },
      ),
    );

/// Stance's `CameraControlPill` (PreRecordingScreen): a stadium at 8 %
/// white, 12 x 6 dp padding, semi-bold labelMedium. Stance's pill shows the
/// current value and opens a menu; here every option is a pill and the
/// selected one is brighter (24 % white).
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.selected, required this.onTap});

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? const Color(0x3DFFFFFF) : const Color(0x14FFFFFF),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
      );
}
