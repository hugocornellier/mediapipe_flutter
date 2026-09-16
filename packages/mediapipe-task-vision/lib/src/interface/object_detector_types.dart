import 'dart:typed_data';

import 'vision_types.dart';
export 'vision_types.dart';

/// Options for the official Object Detector.
final class ObjectDetectorOptions {
  /// Supply exactly one model source. Defaults match the official Python API.
  ObjectDetectorOptions({
    this.modelPath,
    Uint8List? modelBytes,
    this.runningMode = VisionRunningMode.image,
    this.delegate = VisionDelegate.cpu,
    this.displayNamesLocale,
    this.maxResults = -1,
    this.scoreThreshold = 0.0,
    List<String>? categoryAllowlist,
    List<String>? categoryDenylist,
  }) : modelBytes = modelBytes == null
           ? null
           : Uint8List.fromList(modelBytes).asUnmodifiableView(),
       categoryAllowlist = List.unmodifiable(categoryAllowlist ?? const []),
       categoryDenylist = List.unmodifiable(categoryDenylist ?? const []) {
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
    if (!scoreThreshold.isFinite) {
      throw ArgumentError.value(
        scoreThreshold,
        'scoreThreshold',
        'Must be finite',
      );
    }
    // MediaPipe treats a negative count as "no limit"; zero would return
    // nothing, which is a mistake rather than a useful configuration.
    if (maxResults == 0) {
      throw ArgumentError.value(
        maxResults,
        'maxResults',
        'Must be negative for no limit, or a positive count',
      );
    }
    if (this.categoryAllowlist.isNotEmpty && this.categoryDenylist.isNotEmpty) {
      throw ArgumentError(
        'Supply at most one of categoryAllowlist and categoryDenylist.',
      );
    }
    for (final name in [...this.categoryAllowlist, ...this.categoryDenylist]) {
      if (name.isEmpty || name.contains('\u0000')) {
        throw ArgumentError.value(name, 'category', 'Invalid category name');
      }
    }
  }

  /// Filesystem path to an official model, not a Flutter asset key.
  final String? modelPath;

  /// Owned, read-only copy of model bytes, useful with Flutter's rootBundle.
  final Uint8List? modelBytes;

  /// The task mode, fixed for the lifetime of this detector.
  final VisionRunningMode runningMode;

  /// Inference backend. Recreate the task to change it.
  final VisionDelegate delegate;

  /// Locale for display names, as embedded in the model metadata.
  final String? displayNamesLocale;

  /// Maximum detections to return; negative for MediaPipe's own limit.
  final int maxResults;

  /// Minimum score for a detection to be returned.
  final double scoreThreshold;

  /// Category names to keep. Mutually exclusive with [categoryDenylist].
  final List<String> categoryAllowlist;

  /// Category names to drop. Mutually exclusive with [categoryAllowlist].
  final List<String> categoryDenylist;
}

/// An unmodified MediaPipe box, in pixels of the input image.
final class ObjectBoundingBox {
  /// Creates a box without clipping it to image boundaries.
  const ObjectBoundingBox({
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
final class ObjectCategory {
  /// Copies a native category into a Dart value.
  const ObjectCategory({
    required this.index,
    required this.score,
    this.categoryName,
    this.displayName,
  });

  /// Model category index; may be -1 when unspecified.
  final int index;

  /// Model category score.
  final double score;

  /// Model category name, if present.
  final String? categoryName;

  /// Localized display name, if present.
  final String? displayName;
}

/// A detected object with the official model's categories and box.
final class ObjectDetection {
  /// Stores immutable copies of all result lists.
  ObjectDetection({
    required this.boundingBox,
    required List<ObjectCategory> categories,
  }) : categories = List.unmodifiable(categories);

  /// Pixel coordinates in the input image.
  final ObjectBoundingBox boundingBox;

  /// Categories in MediaPipe's original order, highest scoring first.
  final List<ObjectCategory> categories;
}

/// Owned Dart results, valid after subsequent detections and detector disposal.
final class ObjectDetectorResult {
  /// Copies detections into an immutable list.
  ObjectDetectorResult({
    required this.imageWidth,
    required this.imageHeight,
    required List<ObjectDetection> detections,
    this.timestampMilliseconds,
  }) : detections = List.unmodifiable(detections);

  /// Decoded input width, after any EXIF orientation correction.
  final int imageWidth;

  /// Decoded input height, after any EXIF orientation correction.
  final int imageHeight;

  /// Detections in the official pipeline's original order.
  final List<ObjectDetection> detections;

  /// Input video timestamp, or null for an independent still image.
  final int? timestampMilliseconds;
}

/// Failure reported by MediaPipe or its worker isolate.
final class ObjectDetectorException implements Exception {
  /// Creates an error with an optional MediaPipe/Abseil status code.
  const ObjectDetectorException(this.message, {this.statusCode});

  /// Diagnostic text from the native API or worker.
  final String message;

  /// Native status code, or null for an isolate/runtime failure.
  final int? statusCode;

  @override
  String toString() => 'ObjectDetectorException($statusCode): $message';
}
