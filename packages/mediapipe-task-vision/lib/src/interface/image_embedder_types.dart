import 'vision_task_types.dart';
export 'vision_task_types.dart';

/// Configuration for the official Image Embedder.
final class ImageEmbedderOptions extends VisionModelOptions {
  /// The official graph handles preprocessing, normalization and quantization.
  ImageEmbedderOptions({
    super.modelPath,
    super.modelBytes,
    super.runningMode,
    super.delegate,
    this.l2Normalize = false,
    this.quantize = false,
  });

  /// Normalize vectors with L2 norm when the model does not already do so.
  final bool l2Normalize;

  /// Return scalar-quantized bytes rather than floating-point vectors.
  final bool quantize;
}

/// Owned vectors from every embedding head.
final class ImageEmbedderResult {
  /// Store immutable results, valid after native teardown.
  ImageEmbedderResult({
    required List<VisionEmbedding> embeddings,
    required this.imageWidth,
    required this.imageHeight,
    this.timestampMilliseconds,
  }) : embeddings = List.unmodifiable(embeddings);

  /// Embeddings in the official task's order.
  final List<VisionEmbedding> embeddings;

  /// Decoded width of the input image.
  final int imageWidth;

  /// Decoded height of the input image.
  final int imageHeight;

  /// Input video timestamp, or null for a still image.
  final int? timestampMilliseconds;
}
