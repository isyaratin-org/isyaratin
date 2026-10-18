import 'package:flutter/foundation.dart';
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
/// - input: `[1, 32, 400]` float32 (186 base + 214 derived features)
/// - output: `[1, numLabels]` float32 logits/softmax
///
/// This matches the BiLSTM/MGN model trained by `train-new.py` (input
/// `(batch, SEQ_LEN=32, FEAT_DIM=400)`).
///
/// If the model asset is absent, [isAvailable] returns `false` and
/// [recognize] returns an empty list — the app keeps working with typed input.
class SignRecognitionModel {
  SignRecognitionModel._(
    this._interpreter,
    this._labels,
    this.sequenceLength,
    this.inputFeatureDim,
  );

  static const assetPath = 'assets/models/sign_model.tflite';

  final Interpreter _interpreter;
  final List<String> _labels;
  final int sequenceLength;
  final int inputFeatureDim;

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
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final interpreter = Interpreter.fromBuffer(bytes);
      final inputShape = interpreter.getInputTensor(0).shape;
      final outputShape = interpreter.getOutputTensor(0).shape;
      debugPrint(
        'SignRecognitionModel loaded. Input shape: $inputShape, Output shape: $outputShape',
      );

      if (inputShape.length != 3 ||
          inputShape[0] != 1 ||
          inputShape[1] <= 0 ||
          (inputShape[2] != LandmarkExtractor.featureDim &&
              inputShape[2] != LandmarkExtractor.extendedFeatureDim)) {
        interpreter.close();
        throw StateError(
          'Unsupported model input shape $inputShape. Expected [1, frames, 186|400].',
        );
      }
      if (outputShape.length != 2 || outputShape[0] != 1) {
        interpreter.close();
        throw StateError('Unsupported model output shape $outputShape.');
      }

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
        debugPrint('No labels file or failed to parse: $e');
      }
      if (labels.length != outputShape[1]) {
        interpreter.close();
        throw StateError(
          'Model outputs ${outputShape[1]} classes, but labels.txt contains '
          '${labels.length} labels.',
        );
      }
      return SignRecognitionModel._(
        interpreter,
        labels,
        inputShape[1],
        inputShape[2],
      );
    } catch (e, stack) {
      debugPrint('Failed to load SignRecognitionModel: $e\n$stack');
      return null;
    }
  }

  /// Converts the 186-dim camera sequence into the model's actual input.
  Float32List prepareInput(Float32List baseSequence) {
    final expected = sequenceLength * LandmarkExtractor.featureDim;
    if (baseSequence.length != expected) {
      throw ArgumentError(
        'Expected $expected base floats '
        '(${sequenceLength}x${LandmarkExtractor.featureDim}), '
        'got ${baseSequence.length}.',
      );
    }
    if (inputFeatureDim == LandmarkExtractor.featureDim) return baseSequence;
    return LandmarkExtractor.extendSequence(baseSequence, sequenceLength);
  }

  /// Runs inference on the input shape declared by the bundled model.
  ///
  /// Returns the top predictions sorted by confidence, or an empty list when
  /// the model is closed or the input is invalid.
  List<SignPrediction> recognize(Float32List sequence) {
    if (_closed) return const [];
    final expected = sequenceLength * inputFeatureDim;
    if (sequence.length != expected) {
      throw ArgumentError(
        'Model expects $expected floats '
        '(${sequenceLength}x$inputFeatureDim), got ${sequence.length}.',
      );
    }
    try {
      final input = [
        List.generate(
          sequenceLength,
          (i) => List<double>.generate(
            inputFeatureDim,
            (j) => sequence[i * inputFeatureDim + j],
          ),
        ),
      ];
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
    } catch (e, stack) {
      debugPrint('SignRecognitionModel inference error: $e\n$stack');
      return const [];
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _interpreter.close();
  }
}
