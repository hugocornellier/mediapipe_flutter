import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart' as core;

import '../capabilities.dart';
import '../results/decoders.dart';
import '../runner/native_tasks.dart';
import '../runner/text_task_runner.dart';
import '../types/format_context.dart';
import '../types/options.dart';
import '../types/results.dart';

/// Google's Text Embedder: one vector per model head, for the classic
/// embedders and EmbeddingGemma alike.
///
/// One class on every platform. Google's native runtime serves it on a
/// worker isolate on macOS, Linux, Windows and iOS; its Android SDK and
/// browser runtime serve the classic embedders through the registered
/// platform plugin. EmbeddingGemma (`TextModels.embeddingGemma`) runs on
/// Google's macOS engine today, which
/// `queryTextEmbedderCapabilities(TextModels.embeddingGemma)` reports.
///
/// ```dart
/// final task = await TextEmbedder.create(
///   TextEmbedderOptions(model: TextModels.embeddingGemma),
/// );
/// final query = await task.embed(
///   'How do I grow tomatoes?',
///   formatContext: TextFormatContext(taskType: EmbeddingType.retrievalQuery),
/// );
/// await task.dispose();
/// ```
/// Calls run one at a time, in call order. A `Future` cannot cancel native
/// work; `dispose()` waits for work already accepted and is idempotent.
final class TextEmbedder {
  TextEmbedder._(this._task, this.delegate);
  final TextTaskSession<TextEmbedderInput, TextEmbedderResult> _task;

  /// The processor the task runs on, fixed at creation.
  final Delegate delegate;

  /// Resolves the model and opens Google's task off the calling isolate.
  static Future<TextEmbedder> create(TextEmbedderOptions options) async =>
      TextEmbedder._(
        TextTaskSession(
          'TextEmbedder',
          await openClassicTextTask(
            options,
            capabilities: () => queryTextEmbedderCapabilities(options.model),
            task: 'text_embedder',
            settings: {
              'l2Normalize': options.l2Normalize,
              'quantize': options.quantize,
            },
            decode: decodeTextEmbedderResult,
            text: _browserText,
            native: openNativeTextEmbedder,
          ),
        ),
        options.delegate,
      );

  /// Embeds [text]. A [formatContext] has Google's embedder format the
  /// prompt for what the vector is for, as EmbeddingGemma expects; models
  /// without prompt formatting ignore it.
  Future<TextEmbedderResult> embed(
    String text, {
    TextFormatContext? formatContext,
  }) => _task.run(text, (text, formatContext));

  /// Cosine similarity of two embeddings of the same representation and
  /// size, computed in Dart so every platform gives the same answer.
  /// Quantized bytes are read as signed 8-bit values, as Google's APIs do.
  static double cosineSimilarity(Embedding a, Embedding b) =>
      core.cosineSimilarity(a, b);

  /// Finishes accepted work and releases Google's task. Repeated calls return
  /// the same completion; any other call afterwards throws [StateError].
  Future<void> dispose() => _task.dispose();
}

/// Google's browser and Android text embedders take no format context.
String _browserText(TextEmbedderInput input) {
  if (input.$2 != null) {
    throw const RuntimeUnavailableException(
      "Google's browser and Android text embedders take no format context.",
      fix:
          'Embed without formatContext there, or run the model on a '
          'platform whose capability query lists it.',
    );
  }
  return input.$1;
}
