import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../recording/recording.dart';
import 'app_scope.dart';
import 'app_theme.dart';
import 'app_widgets.dart';

/// Our own page (Stance has none), styled like its list screens: Home's
/// 44 dp circle back button and headlineLarge title over 16 dp cards at
/// 4 % white. Each raw CSV can be shared off the phone, or all at once.
class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key, this.share = shareRecordings});

  /// Hands the files to the system share sheet.
  final Future<void> Function(List<File> files) share;

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  late Future<List<File>> _files = _store.list();

  RecordingStore get _store => AppScope.of(context).recordings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  CircleIconButton(
                    icon: Icons.arrow_back,
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  FutureBuilder<List<File>>(
                    future: _files,
                    builder: (context, snap) {
                      final files = snap.data ?? const <File>[];
                      return AppSmallButton(
                        'Share all',
                        key: const Key('shareAllRecordings'),
                        secondary: true,
                        onPressed:
                            files.isEmpty ? null : () => widget.share(files),
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Text('Recordings', style: theme.textTheme.headlineLarge),
            ),
            Expanded(
              child: FutureBuilder<List<File>>(
                future: _files,
                builder: (context, snap) {
                  final files = snap.data;
                  if (files == null) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary));
                  }
                  if (files.isEmpty) {
                    return Center(
                      child: Text('No recordings yet.',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: AppColors.subtitleGray)),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async =>
                        setState(() => _files = _store.list()),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
                      itemCount: files.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _RecordingRow(files[i],
                          onShare: () => widget.share([files[i]])),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingRow extends StatelessWidget {
  const _RecordingRow(this.file, {required this.onShare});

  final File file;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gray = theme.textTheme.bodySmall
        ?.copyWith(color: AppColors.subtitleGray);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardFill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Icon(Icons.description),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(file.uri.pathSegments.last,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${(file.lengthSync() / 1024).toStringAsFixed(0)} KB',
                style: gray),
            Text(file.path, style: gray),
          ]),
        ),
        IconButton(
          key: ValueKey('shareRecording-${file.uri.pathSegments.last}'),
          icon: const Icon(Icons.share),
          tooltip: 'Share',
          onPressed: onShare,
        ),
      ]),
    );
  }
}

/// Sends CSV files to the share sheet.
Future<void> shareRecordings(List<File> files) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [for (final f in files) XFile(f.path, mimeType: 'text/csv')],
      title: files.length == 1 ? 'Share recording' : 'Share recordings',
    ),
  );
}
