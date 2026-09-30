import 'package:mediapipe_core/mediapipe_exception.dart';

import 'embedding_gemma_types.dart';

/// Official EmbeddingGemma task; native implementation requires dart:io.
///
/// ```dart
/// final task = await EmbeddingGemma.create(
///   EmbeddingGemmaOptions(model: TextModels.embeddingGemma),
/// );
/// final result = await task.embed('Hello');
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class EmbeddingGemma {
  EmbeddingGemma._();

  /// Load an official model on a supported platform.
  static Future<EmbeddingGemma> create(EmbeddingGemmaOptions options) =>
      throw const RuntimeUnavailableException(
        'EmbeddingGemma is unavailable on this platform.',
        fix: 'Use macOS arm64 CPU, macOS 14 or later.',
      );

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
