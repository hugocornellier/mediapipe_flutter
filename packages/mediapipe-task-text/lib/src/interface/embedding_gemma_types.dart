import 'dart:math' as math;
import 'dart:typed_data';

/// Official task formatting modes. Formatting is performed inside MediaPipe.
enum EmbeddingTaskType {
  /// Search query.
  retrievalQuery(1),

  /// Search document, with an optional title.
  retrievalDocument(2),

  /// Sentence similarity.
  semanticSimilarity(3),

  /// Classification features.
  classification(4),

  /// Clustering features.
  clustering(5),

  /// Question or answer, selected by [TextRole].
  questionAnswering(6),

  /// Claim or evidence, selected by [TextRole].
  factChecking(7),

  /// Code query or document, selected by [TextRole].
  codeRetrieval(8);

  const EmbeddingTaskType(this.nativeValue);

  /// Value in Google's 1.0.1 C API.
  final int nativeValue;
}

/// Role used by question answering, fact checking and code retrieval.
enum TextRole {
  /// Query prompt.
  query(1),

  /// Document prompt.
  document(2);

  const TextRole(this.nativeValue);

  /// Value in Google's 1.0.1 C API.
  final int nativeValue;
}

/// Passed unchanged to Google's TextEmbedder formatting implementation.
final class TextFormatContext {
  /// Select a task and optional document title.
  TextFormatContext({
    required this.taskType,
    this.title,
    this.role = TextRole.query,
  }) {
    if (title?.contains('\u0000') ?? false) {
      throw ArgumentError.value(title, 'title', 'Must not contain NUL.');
    }
  }

  /// Purpose of this embedding.
  final EmbeddingTaskType taskType;

  /// Optional document title; null is passed as a null native pointer.
  final String? title;

  /// Query or document role.
  final TextRole role;
}

/// Inference backend requested when creating a modern text task.
enum TextDelegate {
  /// CPU inference, currently supported on macOS arm64.
  cpu,

  /// Reserved for platforms with validated GPU support; rejected on macOS.
  gpu,
}

/// Configuration for the official EmbeddingGemma task pipeline.
final class EmbeddingGemmaOptions {
  /// Supply exactly one model source. Models are separate optional downloads.
  EmbeddingGemmaOptions({
    this.modelPath,
    Uint8List? modelBytes,
    this.delegate = TextDelegate.cpu,
    this.l2Normalize = false,
    this.quantize = false,
  }) : modelBytes = modelBytes == null
           ? null
           : Uint8List.fromList(modelBytes).asUnmodifiableView() {
    if ((modelPath == null) == (modelBytes == null)) {
      throw ArgumentError('Supply exactly one of modelPath and modelBytes.');
    }
    if (modelPath != null &&
        (modelPath!.isEmpty || modelPath!.contains('\u0000'))) {
      throw ArgumentError.value(
        modelPath,
        'modelPath',
        'Expected a nonempty filesystem path without NUL.',
      );
    }
    if (modelBytes != null &&
        (modelBytes.isEmpty || modelBytes.length > 0xffffffff)) {
      throw ArgumentError('modelBytes must contain 1 to 2^32-1 bytes.');
    }
  }

  /// Filesystem path, not a Flutter asset key. Prefer this for large models.
  final String? modelPath;

  /// Owned model bytes for applications using Flutter assets.
  final Uint8List? modelBytes;

  /// Backend, fixed at task creation. No silent fallback is performed.
  final TextDelegate delegate;

  /// Google's optional L2 normalization (false by default).
  final bool l2Normalize;

  /// Google's optional scalar quantization of the output vector.
  final bool quantize;
}

/// An owned embedding; remains valid after subsequent inference and disposal.
final class TextEmbedding {
  /// Copies the returned native values into immutable Dart storage.
  TextEmbedding({
    Float32List? floatValues,
    Uint8List? quantizedValues,
    required this.headIndex,
    this.headName,
  }) : floatValues = floatValues == null
           ? null
           : Float32List.fromList(floatValues).asUnmodifiableView(),
       quantizedValues = quantizedValues == null
           ? null
           : Uint8List.fromList(quantizedValues).asUnmodifiableView() {
    if ((floatValues == null) == (quantizedValues == null)) {
      throw ArgumentError('Supply exactly one vector representation.');
    }
  }

  /// Float32 vector, or null when quantization is enabled.
  final Float32List? floatValues;

  /// Raw quantized bytes. Values encode signed int8, as in the official API.
  final Uint8List? quantizedValues;

  /// Output head index from MediaPipe.
  final int headIndex;

  /// Optional output head name from MediaPipe.
  final String? headName;

  /// Number of vector dimensions (768 for the pinned model).
  int get dimensions => floatValues?.length ?? quantizedValues!.length;

  /// Cosine similarity, using the same signed-byte convention as MediaPipe.
  /// Rejects different dimensions/types, nonfinite values and zero vectors.
  static double cosineSimilarity(TextEmbedding a, TextEmbedding b) {
    if (a.dimensions != b.dimensions ||
        (a.floatValues == null) != (b.floatValues == null)) {
      throw ArgumentError('Embeddings must have equal dimensions and types.');
    }
    double dot = 0, normA = 0, normB = 0;
    for (var i = 0; i < a.dimensions; i++) {
      final x =
          a.floatValues?[i] ?? a.quantizedValues![i].toSigned(8).toDouble();
      final y =
          b.floatValues?[i] ?? b.quantizedValues![i].toSigned(8).toDouble();
      if (!x.isFinite || !y.isFinite) {
        throw ArgumentError('Embeddings must be finite.');
      }
      dot += x * y;
      normA += x * x;
      normB += y * y;
    }
    if (normA == 0 || normB == 0) {
      throw ArgumentError('Embeddings must have nonzero norms.');
    }
    return dot / math.sqrt(normA * normB);
  }
}

/// Embeddings copied from an official TextEmbedder result. No dispose needed.
final class TextEmbeddingResult {
  /// Own the ordered embeddings and optional timestamp.
  TextEmbeddingResult({
    required Iterable<TextEmbedding> embeddings,
    this.timestampMs,
  }) : embeddings = List.unmodifiable(embeddings);

  /// Ordered output heads from MediaPipe.
  final List<TextEmbedding> embeddings;

  /// Optional timestamp supplied by MediaPipe (absent for text inputs).
  final int? timestampMs;
}

/// Native task or worker failure, including Google's error message when present.
final class EmbeddingGemmaException implements Exception {
  /// Describe the failed operation and optional native status.
  const EmbeddingGemmaException(this.message, {this.status});

  /// Native or worker error description.
  final String message;

  /// Google C API status, when available.
  final int? status;

  @override
  String toString() =>
      'EmbeddingGemmaException${status == null ? '' : ' ($status)'}: $message';
}
