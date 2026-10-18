import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import 'landmark_extractor.dart';
import 'sign_recognition_model.dart';

/// A live prediction or status emitted by the pipeline.
class LiveSignPrediction {
  const LiveSignPrediction({
    this.label = '',
    this.confidence = 0.0,
    this.bufferProgress = 0.0,
    this.hasPose = false,
    this.handCount = 0,
    this.bufferedFrames = 0,
    this.isRecording = false,
    this.recordedFrames = 0,
    this.recordedDurationSeconds = 0.0,
  });

  final String label;
  final double confidence;

  /// 0.0 → 1.0, progress indication.
  final double bufferProgress;
  final bool hasPose;
  final int handCount;
  final int bufferedFrames;

  /// Recording status
  final bool isRecording;
  final int recordedFrames;
  final double recordedDurationSeconds;
}

/// A recognized sign word from a recorded gesture segment.
class RecognizedSignWord {
  const RecognizedSignWord({
    required this.word,
    required this.confidence,
    required this.startFrame,
    required this.endFrame,
    required this.timeOffsetSeconds,
  });

  final String word;
  final double confidence;
  final int startFrame;
  final int endFrame;
  final double timeOffsetSeconds;
}

/// The result of recognizing an entire recorded gesture sequence.
class RecordedSignResult {
  const RecordedSignResult({
    required this.sentence,
    required this.words,
    required this.totalFrames,
    required this.durationSeconds,
    this.errorMessage,
  });

  final String sentence;
  final List<RecognizedSignWord> words;
  final int totalFrames;
  final double durationSeconds;
  final String? errorMessage;
}

class _WindowPrediction {
  const _WindowPrediction({
    required this.label,
    required this.confidence,
    required this.start,
    required this.end,
  });

  final String label;
  final double confidence;
  final int start;
  final int end;
}

/// Orchestrates BISINDO sign recognition from the camera:
///
/// 1. `hand_landmarker` (MediaPipe, Android) streams 21 hand landmarks.
/// 2. `google_mlkit_pose_detection` processes each frame for 19 pose landmarks.
/// 3. [`LandmarkExtractor`](landmark_extractor.dart) builds the 186-dim vector.
/// 4. Recording Mode: accumulates all frames during gesture recording.
/// 5. Post-recording inference: segments the recording word-by-word using
///    sliding windows and repetition suppression to recognize multi-word sentences.
/// 6. Auto-stop: detects when signer pauses / lowers hands to automatically end recording.
class SignRecognitionPipeline {
  SignRecognitionPipeline({required this.cameraController, required this.model})
    : _extractor = const LandmarkExtractor() {
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
    _initHandLandmarker();
  }

  final CameraController cameraController;
  final SignRecognitionModel model;
  final LandmarkExtractor _extractor;

  PoseDetector? _poseDetector;
  HandLandmarkerPlugin? _handLandmarker;
  StreamSubscription<List<Hand>>? _handSubscription;

  /// Callback when motion has ceased and auto-stop is triggered.
  VoidCallback? onAutoStop;

  /// Latest hand landmarks from the MediaPipe stream.
  List<HandLandmarks> _latestHands = const [];

  final _controller = StreamController<LiveSignPrediction>.broadcast();

  /// Emits live status updates during streaming / recording.
  Stream<LiveSignPrediction> get predictions => _controller.stream;

  bool _disposed = false;
  int _lastProcessedMs = 0;
  // Match training TARGET_FPS of 12.0 (train-new.py). The model was trained on
  // 12 fps sequences, so sampling faster wastes CPU and skews temporal features.
  static const int _targetIntervalMs = 83; // ~12 fps target

  // Non-blocking frame pipeline: the camera stream callback only enqueues the
  // latest frame and returns immediately, so it never blocks on ML inference.
  // A single worker loop drains the queue at its own pace, dropping stale
  // frames when inference is slower than capture.
  final List<_QueuedFrame> _frameQueue = [];
  bool _workerRunning = false;
  bool _workerScheduled = false;

  // Recording state
  bool _isRecording = false;
  bool get isRecording => _isRecording;
  final List<List<double>> _recordedFrames = [];
  DateTime? _recordStartTime;
  int _consecutiveStationaryFrames = 0;
  int _consecutiveNoHandFrames = 0;
  int _framesWithHandsDuringRecording = 0;
  bool _autoStopTriggered = false;

  // Pose caching: shoulders (body-centric reference) barely move during a sign,
  // so re-running ML Kit pose detection every frame is wasteful and is the main
  // cause of slow per-frame recording. Re-detect every few frames, reuse in between.
  PoseLandmarks? _lastPose;
  int _frameCounter = 0;

  // Hand landmarker throttling: the plugin does a full YUV->RGB bitmap
  // conversion in Kotlin on every call, which is the dominant per-frame cost.
  // Feed it at ~12 fps (matching training) instead of camera capture rate.
  int _lastHandProcessMs = 0;
  int _lastHandRotationDegrees = 0;

  void _initHandLandmarker() {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        // CPU delegate is far more reliable than GPU across Android devices;
        // GPU delegate silently fails on many SoCs, leaving hand features
        // zeroed and breaking classification inference.
        _handLandmarker = HandLandmarkerPlugin.create(
          numHands: 2,
          delegate: HandLandmarkerDelegate.cpu,
        );
        _handSubscription = _handLandmarker!.landmarkStream.listen((hands) {
          _latestHands = [
            for (final hand in hands)
              HandLandmarks([
                for (final lm in hand.landmarks)
                  _rotateNormalizedPoint(
                    Point3D(lm.x, lm.y, lm.z),
                    _lastHandRotationDegrees,
                  ),
              ]),
          ];
        });
      } catch (_) {
        _handLandmarker = null;
      }
    }
  }

  /// Begins recording gesture frames for post-stop inference.
  void startRecording() {
    _recordedFrames.clear();
    _isRecording = true;
    _recordStartTime = DateTime.now();
    _consecutiveStationaryFrames = 0;
    _consecutiveNoHandFrames = 0;
    _framesWithHandsDuringRecording = 0;
    _autoStopTriggered = false;
  }

  /// Cancels the current recording without performing inference.
  void cancelRecording() {
    _recordedFrames.clear();
    _isRecording = false;
    _recordStartTime = null;
    _autoStopTriggered = false;
  }

  /// Stops recording and runs word-by-word sequence inference on all recorded frames.
  Future<RecordedSignResult> stopRecordingAndRecognize() async {
    _isRecording = false;
    final recorded = List<List<double>>.from(_recordedFrames);
    _recordedFrames.clear();
    final duration = _recordStartTime != null
        ? (DateTime.now().millisecondsSinceEpoch -
                  _recordStartTime!.millisecondsSinceEpoch) /
              1000.0
        : (recorded.length * 0.08);
    _recordStartTime = null;
    _autoStopTriggered = false;

    if (recorded.length < 5) {
      return RecordedSignResult(
        sentence: '',
        words: const [],
        totalFrames: recorded.length,
        durationSeconds: duration,
        errorMessage:
            'Gerakan terlalu singkat (kurang dari 0.5 detik). Silakan coba rekam kembali.',
      );
    }

    return _recognizeRecordedSequence(recorded, duration);
  }

  /// Feeds one camera frame into the pipeline.
  ///
  /// Call from `cameraController.startImageStream`. This returns immediately:
  /// the frame bytes are copied synchronously (the `CameraImage` buffer is only
  /// valid during the callback) and enqueued for a background worker loop, so
  /// the camera stream is never blocked by ML inference.
  Future<void> processFrame(CameraImage image, int sensorOrientation) async {
    if (_disposed) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Feed MediaPipe hand landmarker (fire-and-forget, native async), but
    // throttled to ~12 fps. The plugin's YUV->RGB conversion is expensive and
    // running it at capture rate (30fps) is the main cause of slow recording.
    // The plugin reads planes[0..2] directly, so guard against non-YUV formats.
    if (image.planes.length >= 3 &&
        now - _lastHandProcessMs >= _targetIntervalMs) {
      _lastHandProcessMs = now;
      _lastHandRotationDegrees = sensorOrientation;
      _handLandmarker?.processFrame(image, sensorOrientation);
    }

    // Copy the YUV frame to NV21 synchronously while the buffer is valid.
    final nv21 = _toNv21Bytes(image);
    if (nv21 == null) return;
    _frameQueue.add(
      _QueuedFrame(
        nv21: nv21,
        width: image.width,
        height: image.height,
        sensorOrientation: sensorOrientation,
        timestampMs: now,
      ),
    );

    if (!_workerScheduled) {
      _workerScheduled = true;
      // Drain on the next microtask so the stream callback returns promptly.
      scheduleMicrotask(_drainQueue);
    }
  }

  Future<void> _drainQueue() async {
    _workerScheduled = false;
    if (_workerRunning || _disposed) return;
    _workerRunning = true;
    try {
      while (!_disposed && _frameQueue.isNotEmpty) {
        // Keep only the newest frame: drop stale frames to stay real-time.
        final frame = _frameQueue.removeLast();
        _frameQueue.clear();

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastProcessedMs < _targetIntervalMs) continue;
        _lastProcessedMs = now;

        await _processOne(frame);
      }
    } finally {
      _workerRunning = false;
    }
  }

  Future<void> _processOne(_QueuedFrame frame) async {
    try {
      // Re-detect pose every 4th frame; reuse the cached pose in between.
      // Shoulders (the body-centric reference) are near-static during a sign,
      // so this cuts pose-detection cost ~4x without hurting accuracy.
      _frameCounter++;
      PoseLandmarks? pose;
      if (_frameCounter % 4 == 1 || _lastPose == null) {
        pose = await _detectPoseFromNv21(
          frame.nv21,
          frame.width,
          frame.height,
          frame.sensorOrientation,
        );
        if (pose != null) _lastPose = pose;
      } else {
        pose = _lastPose;
      }
      final hasPose = pose?.hasPose ?? false;
      final handCount = _latestHands.length;

      final elapsed = _recordStartTime != null
          ? (frame.timestampMs - _recordStartTime!.millisecondsSinceEpoch) /
                1000.0
          : 0.0;

      if (pose == null || !hasPose) {
        if (_isRecording) {
          _consecutiveNoHandFrames++;
          _checkAutoStop();
        }
        _controller.add(
          LiveSignPrediction(
            label: '',
            confidence: 0.0,
            bufferProgress: _isRecording
                ? (_recordedFrames.length / 32.0).clamp(0.0, 1.0)
                : 0.0,
            hasPose: false,
            handCount: handCount,
            bufferedFrames: _recordedFrames.length,
            isRecording: _isRecording,
            recordedFrames: _recordedFrames.length,
            recordedDurationSeconds: elapsed,
          ),
        );
        return;
      }

      final isQuarterTurn =
          frame.sensorOrientation == 90 || frame.sensorOrientation == 270;
      final orientedWidth = isQuarterTurn
          ? frame.height.toDouble()
          : frame.width.toDouble();
      final orientedHeight = isQuarterTurn
          ? frame.width.toDouble()
          : frame.height.toDouble();
      final extracted = _extractor.extractFrame(
        _latestHands,
        pose,
        frameWidth: orientedWidth,
        frameHeight: orientedHeight,
      );
      if (extracted != null && _isRecording) {
        final hasHand =
            handCount > 0 ||
            (extracted.length >= 185 &&
                (extracted[183] > 0.5 || extracted[184] > 0.5));
        if (hasHand) {
          _framesWithHandsDuringRecording++;
          _consecutiveNoHandFrames = 0;

          if (_recordedFrames.isNotEmpty) {
            final prev = _recordedFrames.last;
            final movement = _computeHandMovement(prev, extracted);
            if (movement < 0.035) {
              _consecutiveStationaryFrames++;
            } else {
              _consecutiveStationaryFrames = 0;
            }
          }
        } else {
          _consecutiveNoHandFrames++;
          _consecutiveStationaryFrames = 0;
        }

        _recordedFrames.add(extracted);
        _checkAutoStop();
      }

      _controller.add(
        LiveSignPrediction(
          label: '',
          confidence: 0.0,
          bufferProgress: _isRecording
              ? (_recordedFrames.length / 32.0).clamp(0.0, 1.0)
              : 0.0,
          hasPose: true,
          handCount: handCount,
          bufferedFrames: _recordedFrames.length,
          isRecording: _isRecording,
          recordedFrames: _recordedFrames.length,
          recordedDurationSeconds: elapsed,
        ),
      );
    } catch (e) {
      debugPrint('Pipeline frame error: $e');
    }
  }

  void _checkAutoStop() {
    if (_autoStopTriggered) return;

    // Safety net: never let a recording run forever. If the signer's hands are
    // never detected (e.g. poor lighting), the stationary/no-hand counters may
    // never advance, so force-stop after a max duration.
    final start = _recordStartTime;
    if (start != null) {
      final elapsedMs =
          DateTime.now().millisecondsSinceEpoch - start.millisecondsSinceEpoch;
      if (elapsedMs >= 8000) {
        _autoStopTriggered = true;
        onAutoStop?.call();
        return;
      }
    }

    if (_framesWithHandsDuringRecording >= 12) {
      // At ~12 fps: 20 stationary frames ~ 1.7s of stillness, 18 no-hand frames
      // ~ 1.5s of lowered hands. Lower than before so auto-stop actually fires.
      if (_consecutiveStationaryFrames >= 20 ||
          _consecutiveNoHandFrames >= 18) {
        _autoStopTriggered = true;
        onAutoStop?.call();
      }
    }
  }

  double _computeHandMovement(List<double> prev, List<double> curr) {
    var diff = 0.0;
    for (var i = 0; i < 126; i += 3) {
      final dx = curr[i] - prev[i];
      final dy = curr[i + 1] - prev[i + 1];
      final dz = curr[i + 2] - prev[i + 2];
      diff += math.sqrt(dx * dx + dy * dy + dz * dz);
    }
    return diff / 42.0;
  }

  RecordedSignResult _recognizeRecordedSequence(
    List<List<double>> rawFrames,
    double durationSeconds,
  ) {
    if (rawFrames.isEmpty) {
      return const RecordedSignResult(
        sentence: '',
        words: [],
        totalFrames: 0,
        durationSeconds: 0,
      );
    }

    // Step 1: Activity Trimming (remove initial & trailing idle frames without active hands)
    int firstActive = -1;
    int lastActive = -1;
    for (var i = 0; i < rawFrames.length; i++) {
      final f = rawFrames[i];
      if (f.length >= 185 && (f[183] > 0.5 || f[184] > 0.5)) {
        if (firstActive == -1) firstActive = i;
        lastActive = i;
      }
    }

    List<List<double>> frames;
    if (firstActive != -1 &&
        lastActive != -1 &&
        (lastActive - firstActive + 1) >= 8) {
      final start = math.max(0, firstActive - 2);
      final end = math.min(rawFrames.length, lastActive + 3);
      frames = rawFrames.sublist(start, end);
    } else {
      frames = rawFrames;
    }

    if (frames.length < 5) {
      return RecordedSignResult(
        sentence: '',
        words: const [],
        totalFrames: rawFrames.length,
        durationSeconds: durationSeconds,
        errorMessage:
            'Tangan tidak terdeteksi selama perekaman. Pastikan tangan terlihat jelas di depan kamera.',
      );
    }

    final total = frames.length;
    final windowSize = model.sequenceLength;
    final recognizedWords = <RecognizedSignWord>[];

    // Single-word gesture: sequence length is short (10 to 42 frames, ~0.8s to 3.5s)
    if (total <= 42) {
      final tensor = model.prepareInput(_resampleSequence(frames, windowSize));
      final preds = model.recognize(tensor);
      if (preds.isNotEmpty) {
        final top = preds.first;
        if (top.confidence >= 0.25) {
          recognizedWords.add(
            RecognizedSignWord(
              word: top.label,
              confidence: top.confidence,
              startFrame: 0,
              endFrame: total,
              timeOffsetSeconds: 0.0,
            ),
          );
        }
      }
    } else {
      // Multi-word sequence: Sliding window with repetition suppression & peak selection
      const stride = 10;
      final windowPreds = <_WindowPrediction>[];

      for (var start = 0; start < total; start += stride) {
        final end = math.min(start + windowSize, total);
        final slice = frames.sublist(start, end);
        if (slice.length < 14 && windowPreds.isNotEmpty) break;

        final tensor = model.prepareInput(_resampleSequence(slice, windowSize));
        final preds = model.recognize(tensor);
        if (preds.isNotEmpty) {
          windowPreds.add(
            _WindowPrediction(
              label: preds.first.label,
              confidence: preds.first.confidence,
              start: start,
              end: end,
            ),
          );
        }
        if (end == total) break;
      }

      // Group consecutive identical predictions, picking the peak confidence
      const confidenceThreshold = 0.35;
      _WindowPrediction? currentGroupBest;

      for (final wp in windowPreds) {
        if (wp.confidence < confidenceThreshold) {
          if (currentGroupBest != null) {
            recognizedWords.add(
              RecognizedSignWord(
                word: currentGroupBest.label,
                confidence: currentGroupBest.confidence,
                startFrame: currentGroupBest.start,
                endFrame: currentGroupBest.end,
                timeOffsetSeconds: currentGroupBest.start / 12.0,
              ),
            );
            currentGroupBest = null;
          }
          continue;
        }

        if (currentGroupBest == null) {
          currentGroupBest = wp;
        } else if (wp.label == currentGroupBest.label) {
          if (wp.confidence > currentGroupBest.confidence) {
            currentGroupBest = wp;
          }
        } else {
          recognizedWords.add(
            RecognizedSignWord(
              word: currentGroupBest.label,
              confidence: currentGroupBest.confidence,
              startFrame: currentGroupBest.start,
              endFrame: currentGroupBest.end,
              timeOffsetSeconds: currentGroupBest.start / 12.0,
            ),
          );
          currentGroupBest = wp;
        }
      }

      if (currentGroupBest != null) {
        recognizedWords.add(
          RecognizedSignWord(
            word: currentGroupBest.label,
            confidence: currentGroupBest.confidence,
            startFrame: currentGroupBest.start,
            endFrame: currentGroupBest.end,
            timeOffsetSeconds: currentGroupBest.start / 12.0,
          ),
        );
      }

      // Fallback: if all windows were below threshold, pick the top window overall
      if (recognizedWords.isEmpty && windowPreds.isNotEmpty) {
        windowPreds.sort((a, b) => b.confidence.compareTo(a.confidence));
        final best = windowPreds.first;
        recognizedWords.add(
          RecognizedSignWord(
            word: best.label,
            confidence: best.confidence,
            startFrame: best.start,
            endFrame: best.end,
            timeOffsetSeconds: best.start / 12.0,
          ),
        );
      }
    }

    final sentence = recognizedWords.map((w) => w.word).join(' ');
    return RecordedSignResult(
      sentence: sentence,
      words: recognizedWords,
      totalFrames: rawFrames.length,
      durationSeconds: durationSeconds,
    );
  }

  Float32List _resampleSequence(List<List<double>> frames, int targetLen) {
    final dim = LandmarkExtractor.featureDim;
    final out = Float32List(targetLen * dim);
    if (frames.isEmpty) return out;
    if (frames.length == 1) {
      for (var i = 0; i < targetLen; i++) {
        for (var d = 0; d < dim; d++) {
          out[i * dim + d] = frames[0][d];
        }
      }
      return out;
    }

    for (var i = 0; i < targetLen; i++) {
      final t = i * (frames.length - 1) / (targetLen - 1);
      final i0 = t.floor();
      final i1 = t.ceil();
      final alpha = t - i0;
      final f0 = frames[i0];
      final f1 = frames[i1];
      for (var d = 0; d < dim; d++) {
        out[i * dim + d] = f0[d] * (1.0 - alpha) + f1[d] * alpha;
      }
    }
    return out;
  }

  Future<PoseLandmarks?> _detectPoseFromNv21(
    Uint8List nv21,
    int width,
    int height,
    int sensorOrientation,
  ) async {
    final detector = _poseDetector;
    if (detector == null) return null;
    try {
      final rotation = InputImageRotation.values.firstWhere(
        (r) => r.rawValue == sensorOrientation,
        orElse: () => InputImageRotation.rotation0deg,
      );
      final inputImage = InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: ui.Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      );
      final poses = await detector.processImage(inputImage);
      if (poses.isEmpty) return null;
      return _poseToLandmarks(poses.first, width, height, sensorOrientation);
    } catch (e) {
      debugPrint('_detectPoseFromNv21 error: $e');
      return null;
    }
  }

  /// Converts Android YUV_420_888 (3 separate planes with strides) to flat
  /// NV21 byte buffer. Called synchronously inside the camera callback while
  /// the `CameraImage` planes are still valid.
  Uint8List? _toNv21Bytes(CameraImage image) {
    try {
      if (image.planes.length < 3) {
        // Non-Android / single-plane: concatenate planes as-is.
        final allBytes = WriteBuffer();
        for (final plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        return allBytes.done().buffer.asUint8List();
      }

      final width = image.width;
      final height = image.height;
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final yBuffer = yPlane.bytes;
      final uBuffer = uPlane.bytes;
      final vBuffer = vPlane.bytes;

      final numPixels = width * height;
      final nv21 = Uint8List(numPixels + (numPixels ~/ 2));

      // Copy Y plane row-by-row respecting row stride
      int idy = 0;
      for (int row = 0; row < height; row++) {
        final srcOffset = row * yPlane.bytesPerRow;
        nv21.setRange(idy, idy + width, yBuffer, srcOffset);
        idy += width;
      }

      // Interleave V and U (NV21 expects V first, then U)
      final uvHeight = height ~/ 2;
      final uvWidth = width ~/ 2;
      final uPixelStride = uPlane.bytesPerPixel ?? 1;
      final vPixelStride = vPlane.bytesPerPixel ?? 1;
      final uRowStride = uPlane.bytesPerRow;
      final vRowStride = vPlane.bytesPerRow;

      int iduv = numPixels;
      for (int row = 0; row < uvHeight; row++) {
        for (int col = 0; col < uvWidth; col++) {
          final vIndex = row * vRowStride + col * vPixelStride;
          final uIndex = row * uRowStride + col * uPixelStride;
          nv21[iduv++] = vBuffer[vIndex];
          nv21[iduv++] = uBuffer[uIndex];
        }
      }

      return nv21;
    } catch (e) {
      debugPrint('_toNv21Bytes error: $e');
      return null;
    }
  }

  PoseLandmarks _poseToLandmarks(
    Pose pose,
    int width,
    int height,
    int sensorOrientation,
  ) {
    Point3D? p(PoseLandmarkType type) {
      final lm = pose.landmarks[type];
      if (lm == null || width <= 0 || height <= 0) return null;
      final normalized = Point3D(lm.x / width, lm.y / height, lm.z / width);
      return _rotateNormalizedPoint(normalized, sensorOrientation);
    }

    return PoseLandmarks(
      nose: p(PoseLandmarkType.nose),
      leftEyeInner: p(PoseLandmarkType.leftEyeInner),
      leftEye: p(PoseLandmarkType.leftEye),
      leftEyeOuter: p(PoseLandmarkType.leftEyeOuter),
      rightEyeInner: p(PoseLandmarkType.rightEyeInner),
      rightEye: p(PoseLandmarkType.rightEye),
      rightEyeOuter: p(PoseLandmarkType.rightEyeOuter),
      leftEar: p(PoseLandmarkType.leftEar),
      rightEar: p(PoseLandmarkType.rightEar),
      leftMouth: p(PoseLandmarkType.leftMouth),
      rightMouth: p(PoseLandmarkType.rightMouth),
      leftShoulder: p(PoseLandmarkType.leftShoulder),
      rightShoulder: p(PoseLandmarkType.rightShoulder),
      leftElbow: p(PoseLandmarkType.leftElbow),
      rightElbow: p(PoseLandmarkType.rightElbow),
      leftWrist: p(PoseLandmarkType.leftWrist),
      rightWrist: p(PoseLandmarkType.rightWrist),
      leftHip: p(PoseLandmarkType.leftHip),
      rightHip: p(PoseLandmarkType.rightHip),
    );
  }

  Point3D _rotateNormalizedPoint(Point3D point, int rotationDegrees) {
    switch (rotationDegrees % 360) {
      case 90:
        return Point3D(1.0 - point.y, point.x, point.z);
      case 180:
        return Point3D(1.0 - point.x, 1.0 - point.y, point.z);
      case 270:
        return Point3D(point.y, 1.0 - point.x, point.z);
      default:
        return point;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _frameQueue.clear();
    await _handSubscription?.cancel();
    _handLandmarker?.dispose();
    await _poseDetector?.close();
    await _controller.close();
  }
}

/// A frame waiting to be processed by the worker loop.
///
/// Holds a copied NV21 byte buffer (not the `CameraImage`, whose planes are
/// only valid during the camera stream callback).
class _QueuedFrame {
  const _QueuedFrame({
    required this.nv21,
    required this.width,
    required this.height,
    required this.sensorOrientation,
    required this.timestampMs,
  });

  final Uint8List nv21;
  final int width;
  final int height;
  final int sensorOrientation;
  final int timestampMs;
}
