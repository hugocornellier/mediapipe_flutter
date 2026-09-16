import 'landmark_task_types.dart';
export 'landmark_task_types.dart';

/// Configuration for the official combined face, pose and hand landmark graph.
final class HolisticLandmarkerOptions extends VisionModelOptions {
  /// Defaults match the official task; optional outputs own their buffers.
  HolisticLandmarkerOptions({
    super.modelPath,
    super.modelBytes,
    super.runningMode,
    super.delegate,
    this.minFaceDetectionConfidence = 0.5,
    this.minFaceSuppressionThreshold = 0.5,
    this.minFacePresenceConfidence = 0.5,
    this.minHandLandmarksConfidence = 0.5,
    this.minPoseDetectionConfidence = 0.5,
    this.minPoseSuppressionThreshold = 0.5,
    this.minPosePresenceConfidence = 0.5,
    this.outputFaceBlendshapes = false,
    this.outputPoseSegmentationMask = false,
  }) {
    for (final (name, value) in [
      ('minFaceDetectionConfidence', minFaceDetectionConfidence),
      ('minFaceSuppressionThreshold', minFaceSuppressionThreshold),
      ('minFacePresenceConfidence', minFacePresenceConfidence),
      ('minHandLandmarksConfidence', minHandLandmarksConfidence),
      ('minPoseDetectionConfidence', minPoseDetectionConfidence),
      ('minPoseSuppressionThreshold', minPoseSuppressionThreshold),
      ('minPosePresenceConfidence', minPosePresenceConfidence),
    ]) {
      validateVisionConfidence(value, name);
    }
  }

  /// Minimum face detection confidence.
  final double minFaceDetectionConfidence;

  /// Face nonmaximum suppression threshold.
  final double minFaceSuppressionThreshold;

  /// Minimum face landmark presence confidence.
  final double minFacePresenceConfidence;

  /// Minimum hand landmark confidence.
  final double minHandLandmarksConfidence;

  /// Minimum pose detection confidence.
  final double minPoseDetectionConfidence;

  /// Pose nonmaximum suppression threshold.
  final double minPoseSuppressionThreshold;

  /// Minimum pose landmark presence confidence.
  final double minPosePresenceConfidence;

  /// Include face blendshape predictions when a face is detected.
  final bool outputFaceBlendshapes;

  /// Include the pose foreground confidence mask when available.
  final bool outputPoseSegmentationMask;
}

/// Owned, immutable face, pose and hand outputs for one image or video frame.
final class HolisticLandmarkerResult {
  /// Copy landmarks and optional outputs before native teardown.
  HolisticLandmarkerResult({
    required List<VisionLandmark> faceLandmarks,
    required List<VisionLandmark> poseLandmarks,
    required List<VisionLandmark> poseWorldLandmarks,
    required List<VisionLandmark> leftHandLandmarks,
    required List<VisionLandmark> rightHandLandmarks,
    required List<VisionLandmark> leftHandWorldLandmarks,
    required List<VisionLandmark> rightHandWorldLandmarks,
    List<VisionCategory>? faceBlendshapes,
    this.poseSegmentationMask,
    required this.imageWidth,
    required this.imageHeight,
    this.timestampMilliseconds,
  }) : faceLandmarks = List.unmodifiable(faceLandmarks),
       poseLandmarks = List.unmodifiable(poseLandmarks),
       poseWorldLandmarks = List.unmodifiable(poseWorldLandmarks),
       leftHandLandmarks = List.unmodifiable(leftHandLandmarks),
       rightHandLandmarks = List.unmodifiable(rightHandLandmarks),
       leftHandWorldLandmarks = List.unmodifiable(leftHandWorldLandmarks),
       rightHandWorldLandmarks = List.unmodifiable(rightHandWorldLandmarks),
       faceBlendshapes = faceBlendshapes == null
           ? null
           : List.unmodifiable(faceBlendshapes);

  /// Normalized face landmark coordinates.
  final List<VisionLandmark> faceLandmarks;

  /// Normalized pose landmark coordinates.
  final List<VisionLandmark> poseLandmarks;

  /// Pose world coordinates in meters.
  final List<VisionLandmark> poseWorldLandmarks;

  /// Normalized left hand landmark coordinates.
  final List<VisionLandmark> leftHandLandmarks;

  /// Normalized right hand landmark coordinates.
  final List<VisionLandmark> rightHandLandmarks;

  /// Left hand world coordinates in meters.
  final List<VisionLandmark> leftHandWorldLandmarks;

  /// Right hand world coordinates in meters.
  final List<VisionLandmark> rightHandWorldLandmarks;

  /// Face blendshapes, or null when absent or not requested.
  final List<VisionCategory>? faceBlendshapes;

  /// Pose foreground confidence mask, or null when absent or not requested.
  final SegmentationMask? poseSegmentationMask;

  /// Decoded width of the input image.
  final int imageWidth;

  /// Decoded height of the input image.
  final int imageHeight;

  /// Input video timestamp, or null for a still image.
  final int? timestampMilliseconds;
}
