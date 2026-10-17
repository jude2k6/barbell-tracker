import 'dart:io';

import 'package:flutter/material.dart';

import '../recording/recording.dart';

class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  late Future<List<File>> _files = RecordingStore().list();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recordings')),
      body: FutureBuilder<List<File>>(
        future: _files,
        builder: (context, snap) {
          final files = snap.data;
          if (files == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (files.isEmpty) {
            return const Center(child: Text('No recordings yet.'));
          }
          return RefreshIndicator(
            onRefresh: () async =>
                setState(() => _files = RecordingStore().list()),
            child: ListView(
              children: [
                for (final f in files)
                  ListTile(
                    leading: const Icon(Icons.description),
                    title: Text(f.uri.pathSegments.last),
                    subtitle: Text(
                        '${(f.lengthSync() / 1024).toStringAsFixed(0)} KB\n${f.path}'),
                    isThreeLine: true,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
