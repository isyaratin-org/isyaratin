import 'dart:math' as math;

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
      // Fallback: assume the single hand is on the left side of the frame.
      return wrist != null && wrist.x > 0.5
          ? (left: null, right: hand)
          : (left: hand, right: null);
    }
    // Two hands: sort by wrist x position.
    final sorted = [...hands]
      ..sort((a, b) {
        final ax = a.landmarks.isNotEmpty ? a.landmarks[0].x : 0.0;
        final bx = b.landmarks.isNotEmpty ? b.landmarks[0].x : 0.0;
        return ax.compareTo(bx);
      });
    return (left: sorted[0], right: sorted[1]);
  }

  /// Builds the 186-dim feature vector for one frame.
  ///
  /// Returns `null` when no pose is detected (no body-centric reference).
  List<double>? extractFrame(List<HandLandmarks> hands, PoseLandmarks pose) {
    if (!pose.hasPose) return null;

    final origin = Point3D(
      (pose.leftShoulder!.x + pose.rightShoulder!.x) / 2,
      (pose.leftShoulder!.y + pose.rightShoulder!.y) / 2,
      (pose.leftShoulder!.z + pose.rightShoulder!.z) / 2,
    );
    final scale = _dist(pose.leftShoulder!, pose.rightShoulder!);
    if (scale < 1e-6) return null;

    final assigned = assignHands(hands, pose);
    final features = <double>[];

    // Left hand (63) then right hand (63).
    for (final hand in [assigned.left, assigned.right]) {
      if (hand == null) {
        features.addAll(List.filled(63, 0.0));
      } else {
        for (final landmark in hand.landmarks.take(21)) {
          features.addAll(_normalize(landmark, origin, scale));
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
        features.addAll(_normalize(landmark, origin, scale));
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

  List<double> _normalize(Point3D p, Point3D origin, double scale) => [
    (p.x - origin.x) / scale,
    (p.y - origin.y) / scale,
    (p.z - origin.z) / scale,
  ];

  double _dist(Point3D a, Point3D b) => math.sqrt(_dist2(a, b));

  double _dist2(Point3D a, Point3D b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return dx * dx + dy * dy + dz * dz;
  }
}
