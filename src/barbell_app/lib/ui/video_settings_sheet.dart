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
          Widget row(String label, Widget control) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
                  control,
                ]),
              );
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              row(
                'Camera',
                SegmentedButton<VideoLens>(
                  segments: [
                    for (final l in VideoLens.values)
                      ButtonSegment(value: l, label: Text(l.label)),
                  ],
                  selected: {s.lens},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => store.update(s.copyWith(lens: v.first)),
                ),
              ),
              row(
                'Quality',
                SegmentedButton<VideoQuality>(
                  segments: [
                    for (final q in VideoQuality.values)
                      ButtonSegment(value: q, label: Text(q.label)),
                  ],
                  selected: {s.quality},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => store.update(s.copyWith(quality: v.first)),
                ),
              ),
              row(
                'Frame rate',
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 30, label: Text('30')),
                    ButtonSegment(value: 60, label: Text('60')),
                  ],
                  selected: {s.fps},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => store.update(s.copyWith(fps: v.first)),
                ),
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
