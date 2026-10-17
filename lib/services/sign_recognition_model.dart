import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'landmark_extractor.dart';

/// A single sign-language prediction from the sequence model.
class SignPrediction {
  const SignPrediction({required this.label, required this.confidence});
  final String label;
  final double confidence;
}

/// Loads and runs the TensorFlow Lite BISINDO sequence model.
///
/// The model file is expected at `assets/models/sign_model.tflite` with:
/// - input: `[1, 32, 186]` float32 (32 frames of 186-dim landmarks)
/// - output: `[1, numLabels]` float32 logits/softmax
///
/// This matches the BiLSTM/MGN model trained by `train-new.py` (input
/// `(batch, SEQ_LEN=32, FEAT_DIM=186)`).
///
/// If the model asset is absent, [isAvailable] returns `false` and
/// [recognize] returns an empty list — the app keeps working with typed input.
class SignRecognitionModel {
  SignRecognitionModel._(this._interpreter, this._labels);

  static const assetPath = 'assets/models/sign_model.tflite';

  final Interpreter _interpreter;
  final List<String> _labels;

  bool _closed = false;

  /// Whether a model is bundled in the app assets.
  static Future<bool> isModelBundled() async {
    try {
      await rootBundle.load(assetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads the bundled model. Returns `null` when no model is present.
  static Future<SignRecognitionModel?> load() async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final interpreter = Interpreter.fromBuffer(bytes);
      final inputShape = interpreter.getInputTensor(0).shape;
      final outputShape = interpreter.getOutputTensor(0).shape;
      // ignore: avoid_print
      print(
        'SignRecognitionModel loaded. Input shape: $inputShape, Output shape: $outputShape',
      );

      final labels = <String>[];
      try {
        final raw = await rootBundle.loadString('assets/models/labels.txt');
        labels.addAll(
          raw
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty),
        );
      } catch (e) {
        // ignore: avoid_print
        print('No labels file or failed to parse: $e');
      }
      return SignRecognitionModel._(interpreter, labels);
    } catch (e, stack) {
      // ignore: avoid_print
      print('Failed to load SignRecognitionModel: $e\n$stack');
      return null;
    }
  }

  /// Runs inference on a `(1, 32, 186)` float32 sequence.
  ///
  /// Returns the top predictions sorted by confidence, or an empty list when
  /// the model is closed or the input is invalid.
  List<SignPrediction> recognize(Float32List sequence) {
    if (_closed) return const [];
    final expected = LandmarkExtractor.seqLen * LandmarkExtractor.featureDim;
    if (sequence.length != expected) {
      throw ArgumentError(
        'Model expects $expected floats (32x186), got ${sequence.length}.',
      );
    }
    final input = [sequence];
    final outputShape = _interpreter.getOutputTensor(0).shape;
    final output = List.generate(
      outputShape[0],
      (_) => List<double>.filled(outputShape[1], 0.0),
    );
    _interpreter.run(input, output);
    final scores = output.first;
    final indexed = <(int, double)>[
      for (var i = 0; i < scores.length; i++) (i, scores[i]),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return [
      for (final (index, score) in indexed)
        SignPrediction(
          label: index < _labels.length ? _labels[index] : 'Isyarat $index',
          confidence: score,
        ),
    ];
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _interpreter.close();
  }
}
