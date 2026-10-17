import 'dart:typed_data';

import 'landmark_extractor.dart';

/// Maintains a rolling window of the most recent [LandmarkExtractor.seqLen]
/// feature frames (186-dim each) and produces the `(1, 32, 186)` input tensor
/// expected by the sequence model.
///
/// Frames are pushed in real time from the camera stream. When fewer than
/// [LandmarkExtractor.seqLen] frames are buffered, the window is padded by
/// repeating the first available frame (matching the training script's
/// upsampling for short sequences).
class SequenceBuffer {
  SequenceBuffer({int capacity = LandmarkExtractor.seqLen})
    : _capacity = capacity;

  final int _capacity;
  final List<List<double>?> _frames = [];

  /// Number of frames currently buffered.
  int get length => _frames.length;

  /// Whether the buffer has reached full capacity.
  bool get isFull => _frames.length >= _capacity;

  /// Pushes a new 186-dim frame. Frames that are `null` (no pose detected)
  /// are skipped so the window only contains valid sign frames.
  void push(List<double>? frame) {
    if (frame == null) return;
    assert(
      frame.length == LandmarkExtractor.featureDim,
      'Expected ${LandmarkExtractor.featureDim}, got ${frame.length}',
    );
    _frames.add(frame);
    if (_frames.length > _capacity) {
      _frames.removeAt(0);
    }
  }

  /// Clears the buffer.
  void reset() => _frames.clear();

  /// Builds the `(1, seqLen, 186)` float32 input tensor.
  ///
  /// If the buffer is empty, returns `null` (no valid sequence yet).
  Float32List? buildInput() {
    if (_frames.isEmpty) return null;
    final seqLen = _capacity;
    final dim = LandmarkExtractor.featureDim;
    final input = Float32List(seqLen * dim);

    // Pad by repeating the first frame when the window is short.
    final first = _frames.first!;
    var writeIndex = 0;
    for (var i = 0; i < seqLen; i++) {
      final frame = i < _frames.length ? _frames[i]! : first;
      for (var d = 0; d < dim; d++) {
        input[writeIndex++] = frame[d];
      }
    }
    return input;
  }
}
