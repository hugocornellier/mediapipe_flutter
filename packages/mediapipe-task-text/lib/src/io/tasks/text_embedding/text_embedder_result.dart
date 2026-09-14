import 'dart:ffi';
import 'dart:typed_data';
import 'package:mediapipe_flutter_core/io.dart';
import 'package:mediapipe_flutter_core/interface.dart';
import '../../../interface/embedding_gemma_types.dart';
import '../../classic_text_runtime.dart';
import '../../third_party/mediapipe/embedding_gemma_bindings.dart' as mp;

/// Owned embeddings. Optional dispose is idempotent and does not erase values.
class TextEmbedderResult extends BaseEmbedderResult {
  /// Copy output vectors into unmodifiable Dart storage.
  TextEmbedderResult({
    required Iterable<Embedding> embeddings,
    this.timestampMs,
  }) : embeddings = List.unmodifiable([
         for (final value in embeddings)
           if (value.type == EmbeddingType.float)
             Embedding.float(
               Float32List.fromList(value.floatEmbedding!).asUnmodifiableView(),
               headIndex: value.headIndex,
               headName: value.headName,
             )
           else
             Embedding.quantized(
               Uint8List.fromList(
                 value.quantizedEmbedding!,
               ).asUnmodifiableView(),
               headIndex: value.headIndex,
               headName: value.headName,
             ),
       ]);

  /// Copy a borrowed 1.0.1 result; the caller retains native ownership.
  factory TextEmbedderResult.native(Pointer<mp.MpEmbeddingResult> pointer) =>
      TextEmbedderResult(
        timestampMs: pointer.ref.hasTimestampMs
            ? pointer.ref.timestampMs
            : null,
        embeddings: [
          for (var i = 0; i < pointer.ref.embeddingsCount; i++)
            _copyEmbedding(pointer.ref.embeddings[i]),
        ],
      );

  @override
  final List<Embedding> embeddings;

  /// Optional timestamp supplied by MediaPipe.
  final int? timestampMs;
}

Embedding _copyEmbedding(mp.MpEmbedding value) {
  if ((value.floatEmbedding == nullptr) ==
      (value.quantizedEmbedding == nullptr)) {
    throw StateError('MediaPipe returned an invalid embedding.');
  }
  final name = textTaskString(value.headName);
  return value.floatEmbedding != nullptr
      ? Embedding.float(
          value.floatEmbedding.asTypedList(value.valuesCount),
          headIndex: value.headIndex,
          headName: name,
        )
      : Embedding.quantized(
          value.quantizedEmbedding.asTypedList(value.valuesCount),
          headIndex: value.headIndex,
          headName: name,
        );
}

/// Compute cosine similarity from owned Dart vectors, including signed bytes.
double textEmbeddingCosineSimilarity(BaseEmbedding a, BaseEmbedding b) {
  TextEmbedding convert(BaseEmbedding value) => TextEmbedding(
    floatValues: value.type == EmbeddingType.float
        ? value.floatEmbedding
        : null,
    quantizedValues: value.type == EmbeddingType.quantized
        ? value.quantizedEmbedding
        : null,
    headIndex: value.headIndex,
    headName: value.headName,
  );
  return TextEmbedding.cosineSimilarity(convert(a), convert(b));
}
