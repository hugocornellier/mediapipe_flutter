import 'package:mediapipe_flutter_text/interface.dart';

import '../../../../text_task_backend.dart';
import '../../../backend_text_task.dart';
import '../../pending_text_task.dart';
import 'language_detector_options.dart';
import 'language_detector_executor.dart';
import 'language_detector_result.dart';

/// Official MediaPipe CPU inference: the shared 1.0.1 runtime on a persistent
/// worker isolate, or Google's SDK through a platform plugin where one is
/// installed (text_task_backend.dart).
///
/// Enable core.tasks_runtime in the app's hook settings. Await [dispose] to
/// drain accepted requests, close native resources and wait for worker exit.
class LanguageDetector extends BaseLanguageDetector {
  /// Start loading immediately. Initialization failures reach [detect].
  LanguageDetector(LanguageDetectorOptions options)
    : _task = textTaskBackendFactory == null
          ? PendingTextTask.start(
              name: 'LanguageDetector',
              options: options,
              create: LanguageDetectorExecutor.new,
            )
          : BackendTextTask.start(
              task: 'language_detector',
              options: {
                ...backendModel(options.baseOptions),
                ...backendClassifierOptions(options.classifierOptions),
              },
              decode: (json) => LanguageDetectorResult(
                predictions: [
                  for (final (code, p) in backendLanguages(json))
                    LanguagePrediction(languageCode: code, probability: p),
                ],
              ),
            );

  final TextTaskRunner<LanguageDetectorResult> _task;

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
