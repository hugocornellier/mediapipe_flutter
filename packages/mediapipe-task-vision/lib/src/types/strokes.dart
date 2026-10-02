/// The strokes Google's stateful Interactive Segmenter takes.
library;

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:meta/meta.dart';

/// How a stroke affects the selection, as Google's API names them.
enum BrushMode {
  /// Include the indicated object or area.
  positive(1),

  /// Exclude the indicated area from the selection.
  negative(2),

  /// Select the object enclosed by a polygonal stroke.
  lasso(3);

  const BrushMode(this.nativeValue);

  /// The value Google's C API takes.
  final int nativeValue;
}

/// One stroke of the history a segmentation request carries: its brush mode
/// and its points, normalized to the input image.
@immutable
final class Stroke {
  /// Owns an unmodifiable copy of [points]; a lasso needs at least three.
  Stroke({
    required this.brushMode,
    required List<NormalizedKeypoint> points,
    this.isCompleted = true,
  }) : points = List.unmodifiable(points) {
    if (points.isEmpty || points.length > 0xffffffff) {
      throw ArgumentError('A stroke requires at least one point.');
    }
    if (brushMode == BrushMode.lasso && points.length < 3) {
      throw ArgumentError('A lasso requires at least three points.');
    }
    for (final point in points) {
      if (!point.x.isFinite ||
          !point.y.isFinite ||
          point.x < 0 ||
          point.x > 1 ||
          point.y < 0 ||
          point.y > 1) {
        throw ArgumentError('Stroke coordinates must be finite and in [0, 1].');
      }
    }
  }

  /// Whether the stroke includes, excludes or encloses.
  final BrushMode brushMode;

  /// The stroke's points, from 0 to 1 across the image.
  final List<NormalizedKeypoint> points;

  /// False while the pointer is still down, true once it was released.
  final bool isCompleted;

  @override
  String toString() =>
      'Stroke(${brushMode.name}, ${points.length} points'
      '${isCompleted ? '' : ', in progress'})';
}
