import 'dart:typed_data';

/// Supported modes of the official MediaPipe task.
enum VisionRunningMode {
  /// Independent still images.
  image,

  /// Frames with monotonically increasing timestamps.
  video,
}

/// Options for the official CPU Face Detector.
final class FaceDetectorOptions {
  /// Supply exactly one model source. Thresholds match the official Python API.
  FaceDetectorOptions({
    this.modelPath,
    Uint8List? modelBytes,
    this.runningMode = VisionRunningMode.image,
    this.minDetectionConfidence = 0.5,
    this.minSuppressionThreshold = 0.3,
  }) : modelBytes = modelBytes == null
           ? null
           : Uint8List.fromList(modelBytes).asUnmodifiableView() {
    if ((modelPath == null) == (modelBytes == null)) {
      throw ArgumentError('Supply exactly one of modelPath and modelBytes.');
    }
    if (modelPath != null &&
        (modelPath!.isEmpty || modelPath!.contains('\u0000'))) {
      throw ArgumentError.value(modelPath, 'modelPath', 'Invalid path');
    }
    if (modelBytes != null && modelBytes.isEmpty) {
      throw ArgumentError.value(modelBytes, 'modelBytes', 'Must not be empty');
    }
    for (final entry in {
      'minDetectionConfidence': minDetectionConfidence,
      'minSuppressionThreshold': minSuppressionThreshold,
    }.entries) {
      if (!entry.value.isFinite || entry.value < 0 || entry.value > 1) {
        throw ArgumentError.value(entry.value, entry.key, 'Must be in [0, 1]');
      }
    }
  }

  /// Filesystem path to an official model, not a Flutter asset key.
  final String? modelPath;

  /// Owned, read-only copy of model bytes, useful with Flutter's rootBundle.
  final Uint8List? modelBytes;

  /// The task mode, fixed for the lifetime of this detector.
  final VisionRunningMode runningMode;

  /// Minimum score for a detection to be returned.
  final double minDetectionConfidence;

  /// Intersection threshold used by MediaPipe's non-maximum suppression.
  final double minSuppressionThreshold;
}

/// Channel order for unsigned 8-bit input pixels.
enum VisionPixelFormat {
  /// Red, green, blue.
  rgb(3),

  /// Red, green, blue, alpha. This is not BGRA.
  rgba(4),

  /// Blue, green, red, alpha, as supplied by macOS cameras.
  /// Converted to RGBA on the inference worker before entering MediaPipe.
  bgra(4);

  const VisionPixelFormat(this.channels);

  /// Number of bytes per pixel.
  final int channels;
}

/// Input image. Pixel buffers are copied; callers never own native pointers.
final class VisionImage {
  /// Decode a file with MediaPipe's official image loader, including EXIF.
  VisionImage.fromFile(String path)
    : path = path,
      pixels = null,
      width = null,
      height = null,
      format = null,
      bytesPerRow = null {
    if (path.isEmpty || path.contains('\u0000')) {
      throw ArgumentError.value(path, 'path', 'Invalid path');
    }
  }

  /// Copy RGB, RGBA, or BGRA bytes, optionally including camera row padding.
  ///
  /// [bytesPerRow] defaults to width times channel count. The buffer must have
  /// exactly height times bytesPerRow bytes. Row padding is removed on the
  /// inference worker; no resizing, rotation, or model normalization is done here.
  VisionImage.fromPixels({
    required Uint8List pixels,
    required int width,
    required int height,
    required VisionPixelFormat format,
    int? bytesPerRow,
  }) : path = null,
       width = width,
       height = height,
       format = format,
       bytesPerRow = bytesPerRow ?? width * format.channels,
       pixels = Uint8List.fromList(pixels).asUnmodifiableView() {
    final rowSize = this.bytesPerRow!;
    if (width <= 0 ||
        height <= 0 ||
        width > 0x7fffffff ||
        height > 0x7fffffff ||
        rowSize < width * format.channels ||
        rowSize > 0x7fffffff ||
        height > 0x7fffffff ~/ rowSize) {
      throw ArgumentError(
        'Image dimensions must be positive and fit the C API.',
      );
    }
    final size = rowSize * height;
    if (pixels.length != size) {
      throw ArgumentError(
        'Expected $size pixel-buffer bytes, received ${pixels.length}.',
      );
    }
  }

  /// Source file, or null for pixel input.
  final String? path;

  /// Owned, read-only pixels, or null for file input.
  final Uint8List? pixels;

  /// Pixel width, resolved by MediaPipe for file input.
  final int? width;

  /// Pixel height, resolved by MediaPipe for file input.
  final int? height;

  /// Channel order, resolved by MediaPipe for file input.
  final VisionPixelFormat? format;

  /// Bytes between the starts of adjacent pixel rows, including any padding.
  final int? bytesPerRow;
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

  /// Detection confidence.
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

/// Failure reported by MediaPipe or its worker isolate.
final class FaceDetectorException implements Exception {
  /// Creates an error with an optional MediaPipe/Abseil status code.
  const FaceDetectorException(this.message, {this.statusCode});

  /// Diagnostic text from the native API or worker.
  final String message;

  /// Native status code, or null for an isolate/runtime failure.
  final int? statusCode;

  @override
  String toString() => 'FaceDetectorException($statusCode): $message';
}
