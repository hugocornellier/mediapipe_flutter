import 'dart:math' as math;

import '../../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Image Embedder installed by the web adapter.
final class ImageEmbedder extends SdkVisionTask<ImageEmbedderResult> {
  ImageEmbedder._(super.backend, super.runningMode, super.delegate)
    : super(name: 'ImageEmbedder');

  /// Creates a task through the registered official browser adapter.
  static Future<ImageEmbedder> create(ImageEmbedderOptions options) async =>
      ImageEmbedder._(
        await requireBrowserFactory(imageEmbedderBackendFactory)(options),
        options.runningMode,
        options.delegate,
      );

  /// Embeds a still image or a normalized region, as on native platforms.
  Future<ImageEmbedderResult> embedImage(
    VisionImage image, {
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
  }) => detectImage(
    image,
    rotationDegrees: rotationDegrees,
    regionOfInterest: regionOfInterest,
  );

  /// Embeds a video frame, as on native platforms.
  Future<ImageEmbedderResult> embedForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
  }) => detectForVideo(
    image,
    timestampMilliseconds: timestampMilliseconds,
    rotationDegrees: rotationDegrees,
    regionOfInterest: regionOfInterest,
  );

  /// Cosine similarity of two embeddings of the same representation, as the
  /// native ImageEmbedder computes it; quantized bytes are signed int8.
  static double cosineSimilarity(
    VisionEmbedding first,
    VisionEmbedding second,
  ) {
    List<double> values(VisionEmbedding e) =>
        e.floatEmbedding ??
        [for (final v in e.quantizedEmbedding!) v.toSigned(8).toDouble()];
    if ((first.floatEmbedding != null) != (second.floatEmbedding != null)) {
      throw ArgumentError('Embedding representations must match.');
    }
    final left = values(first), right = values(second);
    if (left.isEmpty || left.length != right.length) {
      throw ArgumentError('Embedding dimensions must be nonzero and equal.');
    }
    var dot = 0.0, normLeft = 0.0, normRight = 0.0;
    for (var i = 0; i < left.length; i++) {
      dot += left[i] * right[i];
      normLeft += left[i] * left[i];
      normRight += right[i] * right[i];
    }
    if (normLeft == 0 || normRight == 0) {
      throw ArgumentError('Embedding norms must be nonzero.');
    }
    return (dot / math.sqrt(normLeft) / math.sqrt(normRight)).clamp(-1.0, 1.0);
  }
}
