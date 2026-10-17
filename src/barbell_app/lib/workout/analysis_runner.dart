import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../analysis/exercises.dart';
import '../analysis/set_analysis.dart';
import '../sensor/sensor_sample.dart';

/// Signature of [analyzeInBackground]; injected so widget tests can supply
/// a fake engine.
typedef SetAnalyzer = Future<SetAnalysis> Function(
    List<SensorSample> samples, Exercise exercise);

Future<DeadliftModels?>? _deadliftModels;

/// Deadlift TFLite model bytes, loaded once on the main isolate (asset
/// loading doesn't work inside a bare isolate). Null if loading failed, in
/// which case the engine uses its threshold fallback and says so in
/// [SetAnalysis.warnings].
Future<DeadliftModels?> loadDeadliftModels() =>
    _deadliftModels ??= DeadliftModels.loadFromAssets()
        .then<DeadliftModels?>((m) => m)
        .catchError((Object e) {
      debugPrint('Deadlift models unavailable, using fallback: $e');
      return null;
    });

/// Runs [analyzeSet] on a background isolate so the UI stays responsive.
/// Errors thrown by the engine are rethrown here.
Future<SetAnalysis> analyzeInBackground(
    List<SensorSample> samples, Exercise exercise) async {
  final models = exercise.isDeadlift ? await loadDeadliftModels() : null;
  final copy = List<SensorSample>.of(samples, growable: false);
  return Isolate.run(
    () => analyzeSet(copy, exercise, deadliftModels: models),
  ).timeout(const Duration(minutes: 2));
}

/// A short user-facing description of an analysis failure.
String describeAnalysisError(Object error) => switch (error) {
      AnalysisException(:final message) => message,
      UnimplementedError() => 'The analysis engine is not available yet.',
      _ => error.toString(),
    };
