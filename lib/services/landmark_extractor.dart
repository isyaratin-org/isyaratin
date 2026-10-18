import 'dart:math' as math;
import 'dart:typed_data';

/// A single 3D landmark point.
class Point3D {
  const Point3D(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

/// A detected hand with 21 landmarks (MediaPipe Hand Landmarker order).
class HandLandmarks {
  const HandLandmarks(this.landmarks);
  final List<Point3D> landmarks;
}

/// Body pose landmarks relevant to BISINDO sign recognition.
///
/// Mirrors the `SELECTED_POSE_INDICES` from the training script:
/// 11 head + 6 arm/shoulder + 2 torso = 19 landmarks.
class PoseLandmarks {
  const PoseLandmarks({
    required this.nose,
    required this.leftEyeInner,
    required this.leftEye,
    required this.leftEyeOuter,
    required this.rightEyeInner,
    required this.rightEye,
    required this.rightEyeOuter,
    required this.leftEar,
    required this.rightEar,
    required this.leftMouth,
    required this.rightMouth,
    required this.leftShoulder,
    required this.rightShoulder,
    required this.leftElbow,
    required this.rightElbow,
    required this.leftWrist,
    required this.rightWrist,
    required this.leftHip,
    required this.rightHip,
  });

  final Point3D? nose;
  final Point3D? leftEyeInner;
  final Point3D? leftEye;
  final Point3D? leftEyeOuter;
  final Point3D? rightEyeInner;
  final Point3D? rightEye;
  final Point3D? rightEyeOuter;
  final Point3D? leftEar;
  final Point3D? rightEar;
  final Point3D? leftMouth;
  final Point3D? rightMouth;
  final Point3D? leftShoulder;
  final Point3D? rightShoulder;
  final Point3D? leftElbow;
  final Point3D? rightElbow;
  final Point3D? leftWrist;
  final Point3D? rightWrist;
  final Point3D? leftHip;
  final Point3D? rightHip;

  /// The 19 pose landmarks in the exact order used by training
  /// (`HEAD_INDICES + ARM_INDICES + TORSO_INDICES`).
  List<Point3D?> get ordered => [
    nose,
    leftEyeInner,
    leftEye,
    leftEyeOuter,
    rightEyeInner,
    rightEye,
    rightEyeOuter,
    leftEar,
    rightEar,
    leftMouth,
    rightMouth,
    leftShoulder,
    rightShoulder,
    leftElbow,
    rightElbow,
    leftWrist,
    rightWrist,
    leftHip,
    rightHip,
  ];

  bool get hasPose => leftShoulder != null && rightShoulder != null;
}

/// Builds the 186-dimensional feature vector per frame, matching the
/// training script (`train-new.py`):
///
///   - Left Hand  : 21 landmarks x 3 = 63
///   - Right Hand : 21 landmarks x 3 = 63
///   - Pose       : 19 landmarks x 3 = 57 (11 head + 6 arm + 2 torso)
///   - Flags      : [has_left_hand, has_right_hand, has_pose] = 3
///   Total: 63 + 63 + 57 + 3 = 186
///
/// Body-centric normalization:
///   - Origin = midpoint between left and right shoulder (torso_center)
///   - Scale  = Euclidean distance between the two shoulders (torso_scale)
///   - All coordinates are translated to origin and divided by scale.
class LandmarkExtractor {
  const LandmarkExtractor();

  static const int featureDim = 186;
  static const int extendedFeatureDim = 400;
  static const int seqLen = 32;

  /// Determines which detected hand is left vs right.
  ///
  /// Uses the pose wrists when available; otherwise falls back to the
  /// horizontal position of the hand wrist (left side of frame = left hand).
  ({HandLandmarks? left, HandLandmarks? right}) assignHands(
    List<HandLandmarks> hands,
    PoseLandmarks pose,
  ) {
    if (hands.isEmpty) return (left: null, right: null);
    if (hands.length == 1) {
      final hand = hands.first;
      final wrist = hand.landmarks.isNotEmpty ? hand.landmarks[0] : null;
      final poseLeft = pose.leftWrist;
      final poseRight = pose.rightWrist;
      if (poseLeft != null && poseRight != null && wrist != null) {
        final dLeft = _dist2(wrist, poseLeft);
        final dRight = _dist2(wrist, poseRight);
        return dLeft <= dRight
            ? (left: hand, right: null)
            : (left: null, right: hand);
      }
      // Fallback for a signer facing the camera: the anatomical left hand is
      // normally on the right half of the unmirrored camera image.
      return wrist != null && wrist.x > 0.5
          ? (left: hand, right: null)
          : (left: null, right: hand);
    }
    final first = hands[0];
    final second = hands[1];
    final firstWrist = first.landmarks.isNotEmpty ? first.landmarks[0] : null;
    final secondWrist = second.landmarks.isNotEmpty
        ? second.landmarks[0]
        : null;
    if (firstWrist != null &&
        secondWrist != null &&
        pose.leftWrist != null &&
        pose.rightWrist != null) {
      final direct =
          _dist2(firstWrist, pose.leftWrist!) +
          _dist2(secondWrist, pose.rightWrist!);
      final swapped =
          _dist2(firstWrist, pose.rightWrist!) +
          _dist2(secondWrist, pose.leftWrist!);
      return direct <= swapped
          ? (left: first, right: second)
          : (left: second, right: first);
    }
    final sorted = [first, second]
      ..sort((a, b) => b.landmarks[0].x.compareTo(a.landmarks[0].x));
    return (left: sorted[0], right: sorted[1]);
  }

  /// Builds the 186-dim feature vector for one frame.
  ///
  /// Returns `null` when no pose is detected (no body-centric reference).
  List<double>? extractFrame(
    List<HandLandmarks> hands,
    PoseLandmarks pose, {
    double frameWidth = 1.0,
    double frameHeight = 1.0,
  }) {
    if (!pose.hasPose) return null;

    final maxDimension = math.max(frameWidth, frameHeight);
    final sx = maxDimension > 0 ? frameWidth / maxDimension : 1.0;
    final sy = maxDimension > 0 ? frameHeight / maxDimension : 1.0;
    Point3D scalePoint(Point3D p) => Point3D(p.x * sx, p.y * sy, p.z * sx);

    final leftShoulder = scalePoint(pose.leftShoulder!);
    final rightShoulder = scalePoint(pose.rightShoulder!);

    final origin = Point3D(
      (leftShoulder.x + rightShoulder.x) / 2,
      (leftShoulder.y + rightShoulder.y) / 2,
      (leftShoulder.z + rightShoulder.z) / 2,
    );
    // Training uses the shoulder distance in the image plane, not XYZ.
    final scale = _dist2d(leftShoulder, rightShoulder);
    if (scale < 1e-6) return null;

    final assigned = assignHands(hands, pose);
    final features = <double>[];

    // Left hand (63) then right hand (63).
    for (final entry in [
      (hand: assigned.left, poseWrist: pose.leftWrist),
      (hand: assigned.right, poseWrist: pose.rightWrist),
    ]) {
      final hand = entry.hand;
      if (hand == null) {
        features.addAll(List.filled(63, 0.0));
      } else {
        final poseWrist = entry.poseWrist == null
            ? null
            : scalePoint(entry.poseWrist!);
        final wristDepth = poseWrist == null
            ? 0.0
            : (poseWrist.z - origin.z) / scale;
        for (final landmark in hand.landmarks.take(21)) {
          final raw = scalePoint(landmark);
          features.addAll([
            (raw.x - origin.x) / scale,
            (raw.y - origin.y) / scale,
            wristDepth + (raw.z / scale),
          ]);
        }
        // Pad if fewer than 21 landmarks.
        final remaining = 21 - hand.landmarks.length;
        if (remaining > 0) features.addAll(List.filled(remaining * 3, 0.0));
      }
    }

    // Pose (57): 19 landmarks x 3, missing landmarks zeroed.
    for (final landmark in pose.ordered) {
      if (landmark == null) {
        features.addAll(const [0.0, 0.0, 0.0]);
      } else {
        features.addAll(_normalize(scalePoint(landmark), origin, scale));
      }
    }

    // Flags (3).
    final hasLeft = assigned.left != null ? 1.0 : 0.0;
    final hasRight = assigned.right != null ? 1.0 : 0.0;
    final hasPose = 1.0;
    features.addAll([hasLeft, hasRight, hasPose]);

    assert(
      features.length == featureDim,
      'Expected $featureDim, got ${features.length}',
    );
    return features;
  }

  /// Reproduces `compute_extended_features` from holistic_extractor.py.
  /// Converts a flattened [sequenceLength, 186] base sequence into the
  /// [sequenceLength, 400] tensor expected by the current MGN TFLite model.
  static Float32List extendSequence(
    Float32List baseSequence,
    int sequenceLength,
  ) {
    final expected = sequenceLength * featureDim;
    if (baseSequence.length != expected) {
      throw ArgumentError(
        'Expected $expected base features, got ${baseSequence.length}.',
      );
    }

    const coordinateDim = 183;
    const relationOffset = featureDim + coordinateDim;
    final output = Float32List(sequenceLength * extendedFeatureDim);

    double value(int frame, int landmark, int axis) =>
        baseSequence[frame * featureDim + landmark * 3 + axis];
    double flag(int frame, int flagIndex) =>
        baseSequence[frame * featureDim + 183 + flagIndex];
    double distance(int frame, int a, int b) {
      final dx = value(frame, a, 0) - value(frame, b, 0);
      final dy = value(frame, a, 1) - value(frame, b, 1);
      final dz = value(frame, a, 2) - value(frame, b, 2);
      return math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    for (var frame = 0; frame < sequenceLength; frame++) {
      final outStart = frame * extendedFeatureDim;
      final baseStart = frame * featureDim;
      output.setRange(outStart, outStart + featureDim, baseSequence, baseStart);

      if (sequenceLength > 1) {
        final sourceFrame = frame == 0 ? 1 : frame;
        final previousFrame = sourceFrame - 1;
        for (var landmark = 0; landmark < 61; landmark++) {
          final flagIndex = landmark < 21 ? 0 : (landmark < 42 ? 1 : 2);
          final continuous =
              flag(sourceFrame, flagIndex) > 0.5 &&
              flag(previousFrame, flagIndex) > 0.5;
          for (var axis = 0; axis < 3; axis++) {
            output[outStart + featureDim + landmark * 3 + axis] = continuous
                ? value(sourceFrame, landmark, axis) -
                      value(previousFrame, landmark, axis)
                : 0.0;
          }
        }
      }

      final hasLeft = flag(frame, 0) > 0.5 ? 1.0 : 0.0;
      final hasRight = flag(frame, 1) > 0.5 ? 1.0 : 0.0;
      final hasPose = flag(frame, 2) > 0.5 ? 1.0 : 0.0;
      final leftPose = hasLeft * hasPose;
      final rightPose = hasRight * hasPose;
      final bothHands = hasLeft * hasRight;

      const leftWrist = 0;
      const leftThumb = 4;
      const leftIndex = 8;
      const rightWrist = 21;
      const rightThumb = 25;
      const rightIndex = 29;
      const nose = 42;
      const leftEar = 49;
      const rightEar = 50;
      const leftMouth = 51;
      const rightMouth = 52;
      const leftShoulderIndex = 53;
      const rightShoulderIndex = 54;

      final mouth = <double>[
        (value(frame, leftMouth, 0) + value(frame, rightMouth, 0)) * 0.5,
        (value(frame, leftMouth, 1) + value(frame, rightMouth, 1)) * 0.5,
        (value(frame, leftMouth, 2) + value(frame, rightMouth, 2)) * 0.5,
      ];
      final torso = <double>[
        (value(frame, leftShoulderIndex, 0) +
                value(frame, rightShoulderIndex, 0)) *
            0.5,
        (value(frame, leftShoulderIndex, 1) +
                value(frame, rightShoulderIndex, 1)) *
            0.5,
        (value(frame, leftShoulderIndex, 2) +
                value(frame, rightShoulderIndex, 2)) *
            0.5,
      ];
      double distanceToPoint(int landmark, List<double> point) {
        final dx = value(frame, landmark, 0) - point[0];
        final dy = value(frame, landmark, 1) - point[1];
        final dz = value(frame, landmark, 2) - point[2];
        return math.sqrt(dx * dx + dy * dy + dz * dz);
      }

      final relations = <double>[
        distance(frame, leftWrist, rightWrist) * bothHands,
        distance(frame, leftIndex, rightIndex) * bothHands,
        distance(frame, leftWrist, nose) * leftPose,
        distance(frame, rightWrist, nose) * rightPose,
        distanceToPoint(leftWrist, mouth) * leftPose,
        distanceToPoint(rightWrist, mouth) * rightPose,
        distanceToPoint(leftIndex, mouth) * leftPose,
        distanceToPoint(rightIndex, mouth) * rightPose,
        distanceToPoint(leftThumb, mouth) * leftPose,
        distanceToPoint(rightThumb, mouth) * rightPose,
        distance(frame, leftIndex, leftEar) * leftPose,
        distance(frame, rightIndex, rightEar) * rightPose,
        distance(frame, leftWrist, leftEar) * leftPose,
        distance(frame, rightWrist, rightEar) * rightPose,
        distance(frame, leftWrist, leftShoulderIndex) * leftPose,
        distance(frame, rightWrist, rightShoulderIndex) * rightPose,
        distanceToPoint(leftIndex, torso) * leftPose,
        distanceToPoint(rightIndex, torso) * rightPose,
        (value(frame, leftIndex, 1) - value(frame, nose, 1)) * leftPose,
        (value(frame, rightIndex, 1) - value(frame, nose, 1)) * rightPose,
        (value(frame, leftWrist, 1) - torso[1]) * leftPose,
        for (final tip in const [4, 8, 12, 16, 20])
          distance(frame, leftWrist, tip) * hasLeft,
        for (final tip in const [25, 29, 33, 37, 41])
          distance(frame, rightWrist, tip) * hasRight,
      ];
      assert(relations.length == 31);
      output.setRange(
        outStart + relationOffset,
        outStart + extendedFeatureDim,
        relations,
      );
    }
    return output;
  }

  List<double> _normalize(Point3D p, Point3D origin, double scale) => [
    (p.x - origin.x) / scale,
    (p.y - origin.y) / scale,
    (p.z - origin.z) / scale,
  ];

  double _dist2d(Point3D a, Point3D b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _dist2(Point3D a, Point3D b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return dx * dx + dy * dy + dz * dz;
  }
}
