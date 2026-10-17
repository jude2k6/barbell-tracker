/// Loading and running the deadlift TFLite models.
///
/// Model bytes are loaded on the main isolate ([loadFromAssets]) and passed
/// into the analysis isolate, where [TfliteRunner]s are created from them.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'deadlift_pipeline.dart';

class DeadliftModels {
  const DeadliftModels({required this.unet, required this.tcn});

  final Uint8List unet;
  final Uint8List tcn;

  static const _dir = 'assets/models/deadlift';
  static const unetAsset = '$_dir/unet_detrend_2026-04-26_21-14-57.tflite';
  static const tcnAsset = '$_dir/tcn_rep_seg_2026-04-28_09-50-59_epoch10.tflite';

  static Future<DeadliftModels> loadFromAssets() async {
    Future<Uint8List> load(String path) async =>
        (await rootBundle.load(path)).buffer.asUint8List();
    return DeadliftModels(unet: await load(unetAsset), tcn: await load(tcnAsset));
  }

  /// Interpreters for one analysis run. Call [close] on the result's
  /// runners when done.
  DeadliftModelsRunners createRunners() => DeadliftModelsRunners(
        unet: TfliteRunner(unet, window: DeadliftTcnPipeline.unetWindow),
        tcn: TfliteRunner(tcn, window: DeadliftTcnPipeline.tcnWindow),
      );
}

/// One single-threaded interpreter with input and output shape [1, 1, window].
class TfliteRunner implements ModelRunner {
  TfliteRunner(Uint8List model, {required this.window})
      : _interpreter = Interpreter.fromBuffer(
          model,
          options: InterpreterOptions()..threads = 1,
        );

  final int window;
  final Interpreter _interpreter;

  @override
  List<double> predict(List<double> input) {
    final out = [
      [List<double>.filled(window, 0)],
    ];
    _interpreter.run([[input]], out);
    return out[0][0];
  }

  void close() => _interpreter.close();
}
