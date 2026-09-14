import 'package:mediapipe_flutter_core/interface.dart';
import 'package:mediapipe_flutter_text/interface.dart';
import '../../pending_text_task.dart';
import 'text_embedder_options.dart';
import 'text_embedder_executor.dart';
import 'text_embedder_result.dart';

/// Official MediaPipe 1.0.1 CPU inference on a persistent worker isolate.
///
/// Enable core.tasks_runtime in the app's hook settings. Await [dispose] to
/// drain accepted requests, close native resources and wait for worker exit.
class TextEmbedder extends BaseTextEmbedder {
  /// Start loading immediately. Initialization failures reach [embed].
  TextEmbedder(TextEmbedderOptions options)
    : _task = PendingTextTask.start(
        name: 'TextEmbedder',
        options: options,
        create: TextEmbedderExecutor.new,
      );

  final PendingTextTask<TextEmbedderResult> _task;

  /// Load off the calling isolate and report initialization errors now.
  static Future<TextEmbedder> create(TextEmbedderOptions options) async {
    final task = TextEmbedder(options);
    await task._task.ready;
    return task;
  }

  @override
  Future<TextEmbedderResult> embed(String text) => _task.run(text);

  /// Compare owned vectors using MediaPipe's signed int8 convention.
  @override
  Future<double> cosineSimilarity(BaseEmbedding a, BaseEmbedding b) async {
    _task.checkActive();
    await _task.ready;
    return textEmbeddingCosineSimilarity(a, b);
  }

  /// Drain accepted work and close once; safe before initialization completes.
  @override
  Future<void> dispose() => _task.dispose();
}
