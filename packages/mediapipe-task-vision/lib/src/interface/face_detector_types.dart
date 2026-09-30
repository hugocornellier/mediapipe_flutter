import 'vision_task_types.dart';

export 'vision_task_types.dart' show VisionTaskException;
export 'vision_types.dart';

/// Options for the official Face Detector.
final class FaceDetectorOptions extends VisionModelOptions {
  /// Supply exactly one model source. Thresholds match the official Python API.
  FaceDetectorOptions({
    super.model,
    super.modelPath,
    super.modelBytes,
    super.runningMode,
    super.delegate,
    this.minDetectionConfidence = 0.5,
    this.minSuppressionThreshold = 0.3,
  }) {
    for (final entry in {
      'minDetectionConfidence': minDetectionConfidence,
      'minSuppressionThreshold': minSuppressionThreshold,
    }.entries) {
      if (!entry.value.isFinite || entry.value < 0 || entry.value > 1) {
        throw ArgumentError.value(entry.value, entry.key, 'Must be in [0, 1]');
      }
    }
  }

  /// Minimum score for a detection to be returned.
  final double minDetectionConfidence;

  /// Intersection threshold used by MediaPipe's non-maximum suppression.
  final double minSuppressionThreshold;
}

/// An unmodified MediaPipe box, in pixels of the input image.
final class FaceBoundingBox {
  /// Creates a box without clipping it to image boundaries.
  const FaceBoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Left edge in pixels.
  final int left;

  /// Top edge in pixels.
  final int top;

  /// Right edge in pixels.
  final int right;

  /// Bottom edge in pixels.
  final int bottom;

  /// Width in pixels.
  int get width => right - left;

  /// Height in pixels.
  int get height => bottom - top;
}

/// A category returned by MediaPipe.
final class FaceCategory {
  /// Copies a native category into a Dart value.
  const FaceCategory({
    required this.index,
    required this.score,
    this.categoryName,
    this.displayName,
  });

  /// Model category index; may be -1 when unspecified.
  final int index;

  /// Model category score (detection confidence or a blendshape coefficient).
  final double score;

  /// Model category name, if present.
  final String? categoryName;

  /// Localized display name, if present.
  final String? displayName;
}

/// A MediaPipe keypoint normalized to the input image.
final class FaceKeypoint {
  /// Copies a native keypoint without clamping its coordinates.
  const FaceKeypoint({
    required this.x,
    required this.y,
    this.label,
    this.score,
  });

  /// Horizontal coordinate divided by input image width.
  final double x;

  /// Vertical coordinate divided by input image height.
  final double y;

  /// Optional model-provided label.
  final String? label;

  /// Optional keypoint confidence, distinct from detection confidence.
  final double? score;
}

/// A face with the official model's categories, box, and keypoints.
final class FaceDetection {
  /// Stores immutable copies of all result lists.
  FaceDetection({
    required this.boundingBox,
    required List<FaceCategory> categories,
    required List<FaceKeypoint> keypoints,
  }) : categories = List.unmodifiable(categories),
       keypoints = List.unmodifiable(keypoints);

  /// Pixel coordinates in the input image.
  final FaceBoundingBox boundingBox;

  /// Categories in MediaPipe's original order.
  final List<FaceCategory> categories;

  /// BlazeFace order: right eye, left eye, nose tip, mouth, right/left tragion.
  final List<FaceKeypoint> keypoints;
}

/// Owned Dart results, valid after subsequent detections and detector disposal.
final class FaceDetectorResult {
  /// Copies detections into an immutable list.
  FaceDetectorResult({
    required this.imageWidth,
    required this.imageHeight,
    required List<FaceDetection> detections,
    this.timestampMilliseconds,
  }) : detections = List.unmodifiable(detections);

  /// Decoded input width, after any EXIF orientation correction.
  final int imageWidth;

  /// Decoded input height, after any EXIF orientation correction.
  final int imageHeight;

  /// Detections in the official pipeline's original order.
  final List<FaceDetection> detections;

  /// Input video timestamp, or null for an independent still image.
  final int? timestampMilliseconds;
}
