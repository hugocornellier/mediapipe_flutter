import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:mediapipe_flutter_core/interface.dart';
import '../../classic_text_runtime.dart';
import '../../third_party/mediapipe/embedding_gemma_bindings.dart' as mp;
import 'text_embedder_options.dart';
import 'text_embedder_result.dart';

/// Synchronous MediaPipe 1.0.1 owner. Prefer TextEmbedder for Flutter UI work.
class TextEmbedderExecutor extends NativeClassicTextTask<TextEmbedderResult> {
  /// Load the official task using the same runtime as EmbeddingGemma.
  TextEmbedderExecutor(TextEmbedderOptions options) {
    requireTextTasksRuntime();
    using((arena) {
      final native = arena<mp.MpTextEmbedderOptions>();
      fillTextBaseOptions(native.ref.baseOptions, options.baseOptions, arena);
      native.ref.embedderOptions
        ..l2Normalize = options.embedderOptions.l2Normalize
        ..quantize = options.embedderOptions.quantize;
      final output = arena<Pointer<Void>>();
      checkTextStatus((error) => mp.create(native, output, error));
      handle = output.value;
      if (handle == nullptr) {
        throw StateError('MediaPipe returned no TextEmbedder.');
      }
    });
  }

  /// Run Google's tokenizer, embedding model and output transformations.
  TextEmbedderResult embed(String text) {
    checkInput(text);
    return using((arena) {
      final output = arena<mp.MpEmbeddingResult>();
      checkTextStatus(
        (error) => mp.embed(
          handle,
          text.toNativeUtf8(allocator: arena).cast(),
          nullptr,
          output,
          error,
        ),
      );
      try {
        return TextEmbedderResult.native(output);
      } finally {
        mp.closeResult(output);
      }
    });
  }

  /// Compare Dart-owned vectors; native pointers are no longer accepted.
  double cosineSimilarity(BaseEmbedding a, BaseEmbedding b) {
    checkInput('');
    return textEmbeddingCosineSimilarity(a, b);
  }

  @override
  TextEmbedderResult run(String text) => embed(text);

  @override
  void close() {
    if (handle == nullptr) return;
    final task = handle;
    handle = nullptr;
    checkTextStatus((error) => mp.close(task, error));
  }
}
