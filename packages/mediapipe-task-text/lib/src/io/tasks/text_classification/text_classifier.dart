import 'package:mediapipe_flutter_core/io.dart';
import 'package:mediapipe_flutter_text/interface.dart';

import '../../../../text_task_backend.dart';
import '../../../backend_text_task.dart';
import '../../pending_text_task.dart';
import 'text_classifier_options.dart';
import 'text_classifier_executor.dart';
import 'text_classifier_result.dart';

/// Official MediaPipe CPU inference: the shared 1.0.1 runtime on a persistent
/// worker isolate, or Google's SDK through a platform plugin where one is
/// installed (text_task_backend.dart).
///
/// Enable core.tasks_runtime in the app's hook settings. Await [dispose] to
/// drain accepted requests, close native resources and wait for worker exit.
class TextClassifier extends BaseTextClassifier {
  /// Start loading immediately. Initialization failures reach [classify].
  TextClassifier(TextClassifierOptions options)
    : _task = textTaskBackendFactory == null
          ? PendingTextTask.start(
              name: 'TextClassifier',
              options: options,
              create: TextClassifierExecutor.new,
            )
          : BackendTextTask.start(
              task: 'text_classifier',
              options: {
                ...backendModel(options.baseOptions),
                ...backendClassifierOptions(options.classifierOptions),
              },
              decode: (json) => TextClassifierResult(
                classifications: _heads(backendClassifications(json)),
                timestampMs: backendTimestamp(json),
              ),
            );

  final TextTaskRunner<TextClassifierResult> _task;

  /// Load off the calling isolate and report initialization errors now.
  static Future<TextClassifier> create(TextClassifierOptions options) async {
    final task = TextClassifier(options);
    await task._task.ready;
    return task;
  }

  @override
  Future<TextClassifierResult> classify(String text) => _task.run(text);

  /// Drain accepted work and close once; safe before initialization completes.
  @override
  Future<void> dispose() => _task.dispose();
}

List<Classifications> _heads(List<BackendHead> heads) => [
  for (final head in heads)
    Classifications(
      categories: [
        for (final c in head.categories)
          Category(
            index: c.index,
            score: c.score,
            categoryName: c.categoryName,
            displayName: c.displayName,
          ),
      ],
      headIndex: head.headIndex,
      headName: head.headName,
    ),
];
