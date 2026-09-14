import 'package:mediapipe_flutter_text/interface.dart';
import '../../pending_text_task.dart';
import 'language_detector_options.dart';
import 'language_detector_executor.dart';
import 'language_detector_result.dart';

/// Official MediaPipe 1.0.1 CPU inference on a persistent worker isolate.
///
/// Enable core.tasks_runtime in the app's hook settings. Await [dispose] to
/// drain accepted requests, close native resources and wait for worker exit.
class LanguageDetector extends BaseLanguageDetector {
  /// Start loading immediately. Initialization failures reach [detect].
  LanguageDetector(LanguageDetectorOptions options)
    : _task = PendingTextTask.start(
        name: 'LanguageDetector',
        options: options,
        create: LanguageDetectorExecutor.new,
      );

  final PendingTextTask<LanguageDetectorResult> _task;

  /// Load off the calling isolate and report initialization errors now.
  static Future<LanguageDetector> create(
    LanguageDetectorOptions options,
  ) async {
    final task = LanguageDetector(options);
    await task._task.ready;
    return task;
  }

  @override
  Future<LanguageDetectorResult> detect(String text) => _task.run(text);

  /// Drain accepted work and close once; safe before initialization completes.
  @override
  Future<void> dispose() => _task.dispose();
}
