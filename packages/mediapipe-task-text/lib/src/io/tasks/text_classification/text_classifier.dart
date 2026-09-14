import 'package:mediapipe_flutter_text/interface.dart';
import '../../pending_text_task.dart';
import 'text_classifier_options.dart';
import 'text_classifier_executor.dart';
import 'text_classifier_result.dart';

/// Official MediaPipe 1.0.1 CPU inference on a persistent worker isolate.
///
/// Enable core.tasks_runtime in the app's hook settings. Await [dispose] to
/// drain accepted requests, close native resources and wait for worker exit.
class TextClassifier extends BaseTextClassifier {
  /// Start loading immediately. Initialization failures reach [classify].
  TextClassifier(TextClassifierOptions options)
    : _task = PendingTextTask.start(
        name: 'TextClassifier',
        options: options,
        create: TextClassifierExecutor.new,
      );

  final PendingTextTask<TextClassifierResult> _task;

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
