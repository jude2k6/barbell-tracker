import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../analysis/exercises.dart';
import '../recording/recording_csv.dart';
import '../workout/file_log.dart';
import '../workout/recording_import.dart';
import '../workout/session.dart';
import 'app_scope.dart';
import 'format.dart';
import 'workout_flow.dart';

/// A picked file: its name and its text.
typedef PickedTextFile = ({String name, String text});

/// Opens the system file picker (any file type, as Stance's
/// `OpenDocument("*/*")`); null when cancelled.
Future<PickedTextFile?> pickRecordingFile() async {
  final file = await FilePicker.pickFile();
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return (name: file.name, text: utf8.decode(bytes, allowMalformed: true));
}

/// Stance's Home "Import recording" card (debug builds only there) and its
/// "Imported: …" label, notes §24. Pick a file → give exercise and weight
/// → "Processing recording…" → the label, which opens Sessions for that
/// exercise, can share the saved CSV ("Export IMU CSV") and be dismissed.
class RecordingImportCard extends StatefulWidget {
  const RecordingImportCard({
    super.key,
    this.pick = pickRecordingFile,
    this.share = shareImuCsv,
  });

  final Future<PickedTextFile?> Function() pick;

  /// Hands a saved CSV (absolute path) to the share sheet.
  final Future<void> Function(String path) share;

  @override
  State<RecordingImportCard> createState() => _RecordingImportCardState();
}

class _RecordingImportCardState extends State<RecordingImportCard> {
  RecordingImportState _state = const RecordingImportState();

  Future<void> _import() async {
    final app = AppScope.of(context);
    final prior = _state.lastImported;
    try {
      final picked = await widget.pick();
      if (picked == null || !mounted) return;
      setState(() => _state = _state.clearError());
      final parsed = parseRecordingCsv(picked.text);
      final details = await showDialog<_ImportDetails>(
        context: context,
        builder: (_) => _ImportDetailsDialog(
          fileName: picked.name,
          unit: app.preferences?.value.weightUnit ?? WeightUnit.kg,
        ),
      );
      if (details == null || !mounted) return;
      setState(() => _state = RecordingImportState.loading);
      final imported = await importRecordingAsSet(
        parsed,
        exercise: details.exercise,
        weight: details.weight,
        unit: details.unit,
        recordings: app.recordings,
        sessions: app.sessions,
        analyze: app.analyzer,
      );
      if (mounted) setState(() => _state = RecordingImportState(lastImported: imported));
    } catch (e) {
      AppLog.e('HomeImport', 'Recording import failed', e);
      if (mounted) {
        setState(() => _state =
            RecordingImportState(errorMessage: '$e', lastImported: prior));
      }
    }
  }

  Future<void> _export(String relative) async {
    final file = await AppScope.of(context).recordings.resolve(relative);
    await widget.share(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _state.lastImported;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            key: const Key('importRecording'),
            leading: _state.isLoading
                ? const SizedBox.square(
                    dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_open_outlined),
            title: const Text('Import recording'),
            subtitle: Text(_state.isLoading
                ? 'Processing recording…'
                : 'Import a raw recording CSV to replay a set.'),
            onTap: _state.isLoading ? null : _import,
          ),
        ),
        if (_state.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _state.errorMessage!,
              key: const Key('importError'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        if (last != null)
          Card(
            key: const Key('lastImported'),
            margin: const EdgeInsets.only(top: 8),
            child: InkWell(
              onTap: () => openSessions(context, last.exercise),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text('Imported: ${last.exercise.rawValue}',
                            style: theme.textTheme.titleSmall),
                      ),
                      IconButton(
                        key: const Key('dismissLastImport'),
                        tooltip: 'Dismiss last import',
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            setState(() => _state = _state.dismissLast()),
                      ),
                    ]),
                    Text(
                        'Recorded: ${fmtDate(last.recordedAt)} ${fmtTime(last.recordedAt)}',
                        style: theme.textTheme.bodySmall),
                    Text('Tap to open Sessions for this exercise',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    if (last.rawCsvFile case final raw?) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: OutlinedButton(
                          key: const Key('exportImuCsv'),
                          onPressed: () => _export(raw),
                          child: const Text('Export IMU CSV'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Shares a recording CSV (Stance's `shareImuCsvFile`, chooser "Share IMU
/// recording").
Future<void> shareImuCsv(String path) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile(path, mimeType: 'text/csv')],
    title: 'Share IMU recording',
  ));
}

class _ImportDetails {
  const _ImportDetails(this.exercise, this.weight, this.unit);
  final Exercise exercise;
  final double weight;
  final WeightUnit unit;
}

/// Exercise and weight for the imported set. Not in Stance, whose `.dat`
/// files carry both; the unit is the Preferences one, as on Input weight.
class _ImportDetailsDialog extends StatefulWidget {
  const _ImportDetailsDialog({required this.fileName, required this.unit});

  final String fileName;
  final WeightUnit unit;

  @override
  State<_ImportDetailsDialog> createState() => _ImportDetailsDialogState();
}

class _ImportDetailsDialogState extends State<_ImportDetailsDialog> {
  Exercise? _exercise;
  final _weight = TextEditingController();

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  /// Empty means no weight (0), as Stance's empty weight string.
  double? get _parsedWeight {
    final t = _weight.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return 0;
    final w = double.tryParse(t);
    return w != null && w >= 0 ? w : null;
  }

  @override
  Widget build(BuildContext context) {
    final weight = _parsedWeight;
    final ready = _exercise != null && weight != null;
    return AlertDialog(
      title: const Text('Import recording'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.fileName, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            DropdownButtonFormField<Exercise>(
              key: const Key('importExercise'),
              initialValue: _exercise,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Exercise'),
              items: [
                for (final e in Exercise.all)
                  DropdownMenuItem(value: e, child: Text(e.rawValue)),
              ],
              onChanged: (e) => setState(() => _exercise = e),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('importWeight'),
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Weight (optional)',
                suffixText: widget.unit.name,
                errorText: weight == null ? 'Enter a valid weight' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('importContinue'),
          onPressed: ready
              ? () => Navigator.pop(
                  context, _ImportDetails(_exercise!, weight, widget.unit))
              : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
