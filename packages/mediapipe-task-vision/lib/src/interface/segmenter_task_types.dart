import 'dart:typed_data';

import 'interactive_segmenter_types.dart' show SegmentationMask;
import 'vision_task_types.dart';

export 'interactive_segmenter_types.dart'
    show SegmentationMask, SegmentationPoint;
export 'vision_task_types.dart';

/// Owned per-pixel class indices in row-major input-image coordinates.
///
/// Each value indexes the label list of the model that produced it. Values are
/// copied before native memory is freed and stay usable afterwards.
final class CategoryMask {
  /// Copies the native GRAY8 mask without thresholding or remapping.
  CategoryMask({
    required this.width,
    required this.height,
    required Uint8List categories,
  }) : categories = Uint8List.fromList(categories).asUnmodifiableView() {
    if (width <= 0 || height <= 0 || categories.length != width * height) {
      throw ArgumentError('Mask dimensions must match the category buffer.');
    }
  }

  /// Mask width, matching the input image width.
  final int width;

  /// Mask height, matching the input image height.
  final int height;

  /// Owned, read-only class indices, indexed by y * width + x.
  final Uint8List categories;
}

/// Owned masks from Image Segmenter or the legacy Interactive Segmenter.
final class SegmentationResult {
  /// Copies every requested mask and quality score before native teardown.
  SegmentationResult({
    List<SegmentationMask>? confidenceMasks,
    this.categoryMask,
    Float32List? qualityScores,
    List<String> labels = const [],
    required this.imageWidth,
    required this.imageHeight,
    this.timestampMilliseconds,
  }) : labels = List.unmodifiable(labels),
       confidenceMasks = confidenceMasks == null
           ? null
           : List.unmodifiable(confidenceMasks),
       qualityScores = qualityScores == null
           ? null
           : Float32List.fromList(qualityScores).asUnmodifiableView();

  /// One confidence mask per category, or null when they were not requested.
  final List<SegmentationMask>? confidenceMasks;

  /// The winning class per pixel, or null when it was not requested.
  final CategoryMask? categoryMask;

  /// Per-category quality in [0, 1], or null when the model reports none.
  ///
  /// Google's official Python bindings drop this field, so it has no
  /// independent reference output; only its shape and range are checked.
  final Float32List? qualityScores;

  /// The model's category order, indexing both mask kinds. Empty when the
  /// task has no label API, as the legacy Interactive Segmenter does not.
  ///
  /// Repeated on every result because the native task stays on its worker
  /// isolate and cannot be queried from the calling isolate.
  final List<String> labels;

  /// Width of the processed image.
  final int imageWidth;

  /// Height of the processed image.
  final int imageHeight;

  /// Timestamp echoed for video requests, or null in image mode.
  final int? timestampMilliseconds;
}

/// Shared mask selection for both segmenter tasks.
abstract base class SegmentationOutputOptions extends VisionModelOptions {
  /// At least one of the two mask outputs must be requested.
  SegmentationOutputOptions({
    super.modelPath,
    super.modelBytes,
    super.runningMode,
    super.delegate,
    this.outputConfidenceMasks = true,
    this.outputCategoryMask = false,
  }) {
    if (!outputConfidenceMasks && !outputCategoryMask) {
      throw ArgumentError(
        'Request a confidence mask, a category mask or both.',
      );
    }
  }

  /// Emit one float32 confidence mask per category.
  final bool outputConfidenceMasks;

  /// Emit a single uint8 mask holding the winning category per pixel.
  final bool outputCategoryMask;
}

/// Official Image Segmenter model and mask options.
final class ImageSegmenterOptions extends SegmentationOutputOptions {
  /// Supply a compatible official model with segmentation metadata.
  ImageSegmenterOptions({
    super.modelPath,
    super.modelBytes,
    super.runningMode,
    super.delegate,
    super.outputConfidenceMasks,
    super.outputCategoryMask,
    this.displayNamesLocale,
  }) {
    if (displayNamesLocale case final locale?) {
      if (locale.isEmpty || locale.codeUnits.contains(0)) {
        throw ArgumentError.value(
          locale,
          'displayNamesLocale',
          'Invalid locale',
        );
      }
    }
  }

  /// Metadata locale for the label list, defaulting to the model's English.
  final String? displayNamesLocale;
}

/// Official legacy Interactive Segmenter model and mask options.
///
/// This is the stateless MagicTouch API that segments the object under a single
/// point. It is a different task from the stateful `InteractiveSegmenter`,
/// which keeps stroke history on a 1.0.1 runtime. It has no video mode.
final class InteractiveSegmenterLegacyOptions
    extends SegmentationOutputOptions {
  /// Supply the official MagicTouch model built for this API.
  InteractiveSegmenterLegacyOptions({
    super.modelPath,
    super.modelBytes,
    super.delegate,
    super.outputConfidenceMasks,
    super.outputCategoryMask,
  });
}
