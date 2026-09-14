import 'embedding_gemma_types.dart';

/// Official EmbeddingGemma task; native implementation requires dart:io.
final class EmbeddingGemma {
  EmbeddingGemma._();

  /// Load an official model on a supported platform.
  static Future<EmbeddingGemma> create(EmbeddingGemmaOptions options) =>
      throw UnsupportedError('EmbeddingGemma requires macOS arm64 CPU.');

  /// Selected inference backend.
  TextDelegate get delegate =>
      throw UnsupportedError('Native runtime required.');

  /// Embed text with optional official task formatting.
  Future<TextEmbeddingResult> embed(
    String text, {
    TextFormatContext? context,
  }) => throw UnsupportedError('Native runtime required.');

  /// Release the task.
  Future<void> dispose() => throw UnsupportedError('Native runtime required.');
}
