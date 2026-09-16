import 'vision_task_types.dart';
import 'interactive_segmenter_types.dart' show SegmentationMask;
export 'vision_task_types.dart';
export 'interactive_segmenter_types.dart' show SegmentationMask;

/// A normalized-image landmark or a world landmark, in its result's coordinates.
final class VisionLandmark {
  /// Store the official coordinates and optional model confidences.
  const VisionLandmark({
    required this.x,
    required this.y,
    required this.z,
    this.visibility,
    this.presence,
    this.name,
  });

  /// Horizontal image coordinate, or world coordinate in meters.
  final double x;

  /// Vertical image coordinate, or world coordinate in meters.
  final double y;

  /// Depth in the model's image coordinates, or world coordinate in meters.
  final double z;

  /// Confidence that this landmark is visible, when supplied by the model.
  final double? visibility;

  /// Confidence that this landmark is present, when supplied by the model.
  final double? presence;

  /// Optional label provided by model metadata.
  final String? name;
}

/// Shared detection and tracking configuration for hand tasks.
abstract base class HandTrackingOptions extends VisionModelOptions {
  /// Defaults match the official Hand Landmarker and Gesture Recognizer.
  HandTrackingOptions({
    super.modelPath,
    super.modelBytes,
    super.runningMode,
    super.delegate,
    this.numHands = 1,
    this.minHandDetectionConfidence = 0.5,
    this.minHandPresenceConfidence = 0.5,
    this.minTrackingConfidence = 0.5,
  }) {
    validateLandmarkCount(numHands, 'numHands');
    validateVisionConfidence(
      minHandDetectionConfidence,
      'minHandDetectionConfidence',
    );
    validateVisionConfidence(
      minHandPresenceConfidence,
      'minHandPresenceConfidence',
    );
    validateVisionConfidence(minTrackingConfidence, 'minTrackingConfidence');
  }

  /// Maximum number of detected hands.
  final int numHands;

  /// Minimum palm detection confidence.
  final double minHandDetectionConfidence;

  /// Minimum landmark-model hand presence confidence.
  final double minHandPresenceConfidence;

  /// Minimum tracking confidence in video mode.
  final double minTrackingConfidence;
}

/// Official Hand Landmarker model and tracking options.
final class HandLandmarkerOptions extends HandTrackingOptions {
  /// Supply a compatible task bundle and optional tracking thresholds.
  HandLandmarkerOptions({
    super.modelPath,
    super.modelBytes,
    super.runningMode,
    super.delegate,
    super.numHands,
    super.minHandDetectionConfidence,
    super.minHandPresenceConfidence,
    super.minTrackingConfidence,
  });
}

/// Metadata classification filters for canned or custom gestures.
final class GestureClassifierOptions {
  /// Negative [maxResults] returns all matching gestures.
  GestureClassifierOptions({
    this.maxResults = -1,
    this.scoreThreshold = 0.0,
    this.displayNamesLocale,
    List<String>? categoryAllowlist,
    List<String>? categoryDenylist,
  }) : categoryAllowlist = List.unmodifiable(categoryAllowlist ?? const []),
       categoryDenylist = List.unmodifiable(categoryDenylist ?? const []) {
    if (maxResults == 0 ||
        maxResults < -0x80000000 ||
        maxResults > 0x7fffffff ||
        !scoreThreshold.isFinite) {
      throw ArgumentError('Invalid classification limits.');
    }
    if (this.categoryAllowlist.isNotEmpty && this.categoryDenylist.isNotEmpty) {
      throw ArgumentError('Supply at most one category allowlist or denylist.');
    }
    for (final label in [
      ?displayNamesLocale,
      ...this.categoryAllowlist,
      ...this.categoryDenylist,
    ]) {
      if (label.isEmpty || label.contains('\u0000')) {
        throw ArgumentError('Invalid classification label.');
      }
    }
  }

  /// Maximum categories per detected hand; negative returns all categories.
  final int maxResults;

  /// Minimum prediction score to return.
  final double scoreThreshold;

  /// Locale of optional display labels in model metadata.
  final String? displayNamesLocale;

  /// Category labels to include.
  final List<String> categoryAllowlist;

  /// Category labels to exclude, mutually exclusive with the allowlist.
  final List<String> categoryDenylist;
}

/// Official Gesture Recognizer model, tracking and classification options.
final class GestureRecognizerOptions extends HandTrackingOptions {
  /// Supply a compatible task bundle with canned and optional custom gestures.
  GestureRecognizerOptions({
    super.modelPath,
    super.modelBytes,
    super.runningMode,
    super.delegate,
    super.numHands,
    super.minHandDetectionConfidence,
    super.minHandPresenceConfidence,
    super.minTrackingConfidence,
    GestureClassifierOptions? cannedGesturesClassifierOptions,
    GestureClassifierOptions? customGesturesClassifierOptions,
  }) : cannedGesturesClassifierOptions =
           cannedGesturesClassifierOptions ?? GestureClassifierOptions(),
       customGesturesClassifierOptions =
           customGesturesClassifierOptions ?? GestureClassifierOptions();

  /// Filters for the model's built-in gesture categories.
  final GestureClassifierOptions cannedGesturesClassifierOptions;

  /// Filters for custom gesture categories, when present in the task bundle.
  final GestureClassifierOptions customGesturesClassifierOptions;
}

/// Official Pose Landmarker model, tracking and mask options.
final class PoseLandmarkerOptions extends VisionModelOptions {
  /// Defaults match the official pose task.
  PoseLandmarkerOptions({
    super.modelPath,
    super.modelBytes,
    super.runningMode,
    super.delegate,
    this.numPoses = 1,
    this.minPoseDetectionConfidence = 0.5,
    this.minPosePresenceConfidence = 0.5,
    this.minTrackingConfidence = 0.5,
    this.outputSegmentationMasks = false,
  }) {
    validateLandmarkCount(numPoses, 'numPoses');
    validateVisionConfidence(
      minPoseDetectionConfidence,
      'minPoseDetectionConfidence',
    );
    validateVisionConfidence(
      minPosePresenceConfidence,
      'minPosePresenceConfidence',
    );
    validateVisionConfidence(minTrackingConfidence, 'minTrackingConfidence');
  }

  /// Maximum number of detected poses.
  final int numPoses;

  /// Minimum person detection confidence.
  final double minPoseDetectionConfidence;

  /// Minimum pose presence confidence.
  final double minPosePresenceConfidence;

  /// Minimum tracking confidence in video mode.
  final double minTrackingConfidence;

  /// Include an owned float32 foreground mask for each detected pose.
  final bool outputSegmentationMasks;
}

/// Owned Hand Landmarker output, ordered consistently across all three lists.
final class HandLandmarkerResult {
  /// Copy every hand's landmarks and category lists before native teardown.
  HandLandmarkerResult({
    required List<List<VisionCategory>> handedness,
    required List<List<VisionLandmark>> handLandmarks,
    required List<List<VisionLandmark>> handWorldLandmarks,
    required this.imageWidth,
    required this.imageHeight,
    this.timestampMilliseconds,
  }) : handedness = ownVisionLists(handedness),
       handLandmarks = ownVisionLists(handLandmarks),
       handWorldLandmarks = ownVisionLists(handWorldLandmarks);

  /// Left/right category predictions for each hand.
  final List<List<VisionCategory>> handedness;

  /// Image-space coordinates for each hand's 21 landmarks.
  final List<List<VisionLandmark>> handLandmarks;

  /// World coordinates in meters for each hand's 21 landmarks.
  final List<List<VisionLandmark>> handWorldLandmarks;

  /// Decoded width of the input image.
  final int imageWidth;

  /// Decoded height of the input image.
  final int imageHeight;

  /// Input video timestamp, or null for a still image.
  final int? timestampMilliseconds;
}

/// Owned Gesture Recognizer predictions and landmarks for each detected hand.
final class GestureRecognizerResult {
  /// Copy categories and landmarks before native teardown.
  GestureRecognizerResult({
    required List<List<VisionCategory>> gestures,
    required List<List<VisionCategory>> handedness,
    required List<List<VisionLandmark>> handLandmarks,
    required List<List<VisionLandmark>> handWorldLandmarks,
    required this.imageWidth,
    required this.imageHeight,
    this.timestampMilliseconds,
  }) : gestures = ownVisionLists(gestures),
       handedness = ownVisionLists(handedness),
       handLandmarks = ownVisionLists(handLandmarks),
       handWorldLandmarks = ownVisionLists(handWorldLandmarks);

  /// Canned and custom gesture predictions in model order for each hand.
  ///
  /// Each category's index is always -1: canned and custom classifiers number
  /// their labels independently, so a merged index carries no meaning.
  final List<List<VisionCategory>> gestures;

  /// Left/right category predictions for each hand.
  final List<List<VisionCategory>> handedness;

  /// Image-space coordinates for each hand's 21 landmarks.
  final List<List<VisionLandmark>> handLandmarks;

  /// World coordinates in meters for each hand's 21 landmarks.
  final List<List<VisionLandmark>> handWorldLandmarks;

  /// Decoded width of the input image.
  final int imageWidth;

  /// Decoded height of the input image.
  final int imageHeight;

  /// Input video timestamp, or null for a still image.
  final int? timestampMilliseconds;
}

/// Owned pose landmarks and optional foreground masks.
final class PoseLandmarkerResult {
  /// Store immutable lists and owned mask buffers.
  PoseLandmarkerResult({
    required List<List<VisionLandmark>> poseLandmarks,
    required List<List<VisionLandmark>> poseWorldLandmarks,
    List<SegmentationMask>? segmentationMasks,
    required this.imageWidth,
    required this.imageHeight,
    this.timestampMilliseconds,
  }) : poseLandmarks = ownVisionLists(poseLandmarks),
       poseWorldLandmarks = ownVisionLists(poseWorldLandmarks),
       segmentationMasks = segmentationMasks == null
           ? null
           : List.unmodifiable(segmentationMasks);

  /// Image-space coordinates for each pose's 33 landmarks.
  final List<List<VisionLandmark>> poseLandmarks;

  /// World coordinates in meters for each pose's 33 landmarks.
  final List<List<VisionLandmark>> poseWorldLandmarks;

  /// Foreground confidence masks, or null when not requested.
  final List<SegmentationMask>? segmentationMasks;

  /// Decoded width of the input image.
  final int imageWidth;

  /// Decoded height of the input image.
  final int imageHeight;

  /// Input video timestamp, or null for a still image.
  final int? timestampMilliseconds;
}

/// Require a finite model confidence in [0, 1].
void validateVisionConfidence(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'Must be finite and in [0, 1]');
  }
}

/// Require a positive count representable by the native C int.
void validateLandmarkCount(int value, String name) {
  if (value < 1 || value > 0x7fffffff) {
    throw ArgumentError.value(value, name, 'Must be a positive C int');
  }
}

/// Own immutable nested result lists.
List<List<T>> ownVisionLists<T>(List<List<T>> values) =>
    List.unmodifiable(values.map((v) => List<T>.unmodifiable(v)));
