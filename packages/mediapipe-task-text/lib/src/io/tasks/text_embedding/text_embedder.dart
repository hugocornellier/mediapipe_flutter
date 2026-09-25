import 'package:mediapipe_flutter_core/interface.dart';
import 'package:mediapipe_flutter_core/io.dart';
import 'package:mediapipe_flutter_text/interface.dart';

import '../../../../text_task_backend.dart';
import '../../../backend_text_task.dart';
import '../../pending_text_task.dart';
import 'text_embedder_options.dart';
import 'text_embedder_executor.dart';
import 'text_embedder_result.dart';

/// Official MediaPipe CPU inference: the shared 1.0.1 runtime on a persistent
/// worker isolate, or Google's SDK through a platform plugin where one is
/// installed (text_task_backend.dart).
///
/// Enable core.tasks_runtime in the app's hook settings. Await [dispose] to
/// drain accepted requests, close native resources and wait for worker exit.
class TextEmbedder extends BaseTextEmbedder {
  /// Start loading immediately. Initialization failures reach [embed].
  TextEmbedder(TextEmbedderOptions options)
    : _task = textTaskBackendFactory == null
          ? PendingTextTask.start(
              name: 'TextEmbedder',
              options: options,
              create: TextEmbedderExecutor.new,
            )
          : BackendTextTask.start(
              task: 'text_embedder',
              options: {
                ...backendModel(options.baseOptions),
                ...backendEmbedderOptions(options.embedderOptions),
              },
              decode: (json) => TextEmbedderResult(
                embeddings: _embeddings(backendEmbeddings(json)),
                timestampMs: backendTimestamp(json),
              ),
            );

  final TextTaskRunner<TextEmbedderResult> _task;

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

List<Embedding> _embeddings(List<BackendEmbedding> values) => [
  for (final e in values)
    if (e.floats case final floats?)
      Embedding.float(floats, headIndex: e.headIndex, headName: e.headName)
    else
      Embedding.quantized(
        e.quantized!,
        headIndex: e.headIndex,
        headName: e.headName,
      ),
];
