import 'dart:typed_data';

import 'vision_task_types.dart';

export 'vision_task_types.dart' show VisionTaskException;

/// Model and backend for Google's stateful MagicTouch Interactive Segmenter.
final class InteractiveSegmenterOptions extends VisionModelOptions {
  /// Supply exactly one official model path or owned model buffer.
  InteractiveSegmenterOptions({
    super.model,
    super.modelPath,
    super.modelBytes,
    super.delegate,
  });
}

/// The official brush modes; unspecified native mode is intentionally excluded.
enum SegmentationBrushMode {
  /// Include the indicated object or area.
  positive(1),

  /// Exclude the indicated area from the selection.
  negative(2),

  /// Select the object enclosed by a polygonal stroke.
  lasso(3);

  const SegmentationBrushMode(this.nativeValue);

  /// Value used by Google's public ctypes API.
  final int nativeValue;
}

/// A point normalized to the displayed input image, without letterboxing.
final class SegmentationPoint {
  /// Coordinates must be finite and between zero and one, inclusive.
  SegmentationPoint({required this.x, required this.y}) {
    if (!x.isFinite || !y.isFinite || x < 0 || x > 1 || y < 0 || y > 1) {
      throw ArgumentError('Stroke coordinates must be finite and in [0, 1].');
    }
  }

  /// Horizontal coordinate divided by image width.
  final double x;

  /// Vertical coordinate divided by image height.
  final double y;
}

/// An immutable stroke. Pass the entire current history to each segment call.
final class SegmentationStroke {
  /// Copies points; lasso strokes require at least three points.
  SegmentationStroke({
    required this.brushMode,
    required List<SegmentationPoint> points,
    this.isCompleted = true,
  }) : points = List.unmodifiable(points) {
    if (points.isEmpty || points.length > 0xffffffff) {
      throw ArgumentError('A stroke requires at least one point.');
    }
    if (brushMode == SegmentationBrushMode.lasso && points.length < 3) {
      throw ArgumentError('A lasso requires at least three points.');
    }
  }

  /// How these points affect the selected area.
  final SegmentationBrushMode brushMode;

  /// An immutable snapshot of the stroke's normalized points.
  final List<SegmentationPoint> points;

  /// False while drawing; true after the pointer is released.
  final bool isCompleted;
}

/// Original float32 confidence values in row-major input-image coordinates.
///
/// Values are copied before native memory is freed. They remain usable after
/// another inference, image replacement or task disposal. No threshold is applied.
final class SegmentationMask {
  /// Copies confidence values without clamping, smoothing or thresholding.
  SegmentationMask({
    required this.width,
    required this.height,
    required Float32List confidence,
  }) : confidence = Float32List.fromList(confidence).asUnmodifiableView() {
    if (width <= 0 || height <= 0 || confidence.length != width * height) {
      throw ArgumentError('Mask dimensions must match the confidence buffer.');
    }
  }

  /// Mask width, matching the input image width.
  final int width;

  /// Mask height, matching the input image height.
  final int height;

  /// Owned, read-only foreground probabilities, indexed by y * width + x.
  final Float32List confidence;
}
