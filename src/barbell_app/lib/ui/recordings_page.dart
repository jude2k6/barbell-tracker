import 'dart:io';

import 'package:flutter/material.dart';

import '../recording/recording.dart';
import 'stance_theme.dart';
import 'stance_widgets.dart';

/// Our own page (Stance has none), styled like its list screens: Home's
/// 44 dp circle back button and headlineLarge title over 16 dp cards at
/// 4 % white.
class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  late Future<List<File>> _files = RecordingStore().list();

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
              child: Align(
                alignment: Alignment.centerLeft,
                child: CircleIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
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
                            color: StanceColors.primary));
                  }
                  if (files.isEmpty) {
                    return Center(
                      child: Text('No recordings yet.',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: StanceColors.subtitleGray)),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async =>
                        setState(() => _files = RecordingStore().list()),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
                      itemCount: files.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _RecordingRow(files[i]),
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
  const _RecordingRow(this.file);

  final File file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gray = theme.textTheme.bodySmall
        ?.copyWith(color: StanceColors.subtitleGray);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StanceColors.cardFill,
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
      ]),
    );
  }
}
