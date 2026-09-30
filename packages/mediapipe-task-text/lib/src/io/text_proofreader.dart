import 'package:mediapipe_core/mediapipe_exception.dart';

import '../../../capabilities.dart';
import '../interface/text_proofreader_types.dart';
import 'native_text_proofreader.dart';
import 'text_task_worker.dart';

/// Official Proofreader inference and streaming on a persistent worker.
///
/// Enable `mediapipe_core.tasks_runtime: true` in app hook settings.
/// Requests are serialized. Await [dispose] to drain native work and exit.
///
/// ```dart
/// final task = await TextProofreader.create(
///   TextProofreaderOptions(model: TextModels.proofreader),
/// );
/// final result = await task.proofread('Hello');
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class TextProofreader {
  TextProofreader._(this.delegate, this._worker);

  /// Backend fixed at creation.
  final TextDelegate delegate;
  final TextTaskWorker<
    TextProofreaderResult,
    TextProofreaderUpdate,
    TextTaskException
  >
  _worker;

  /// Load the official model off the calling isolate.
  static Future<TextProofreader> create(TextProofreaderOptions options) async {
    await options.prepareModel();
    final support = await queryTextTaskCapabilities(TextTask.proofreader);
    if (support.unavailableReasons[options.delegate] case final reason?) {
      throw RuntimeUnavailableException(
        'TextProofreader is unavailable on this platform.',
        fix: reason,
      );
    }
    return TextProofreader._(
      options.delegate,
      await TextTaskWorker.start(
        name: 'TextProofreader',
        options: options,
        create: NativeTextProofreader.new,
        exception: _exception,
      ),
    );
  }

  /// Correct text and return Google's completed text and granular edits.
  Future<TextProofreaderResult> proofread(String text) => _worker.run(text);

  /// Start on listen and forward Google's owned chunk/correction updates.
  ///
  /// The stream has one subscription. Cancellation suppresses further delivery
  /// and waits for native completion: Google's API has no inference cancel call.
  /// Pausing buffers Dart events; it does not pause native generation.
  Stream<TextProofreaderUpdate> proofreadStream(String text) =>
      _worker.stream(text);

  /// Drain queued requests and active streams, then close the task exactly once.
  Future<void> dispose() => _worker.dispose();
}

TextTaskException _exception(Object error) =>
    error is TextTaskException ? error : TextTaskException(error.toString());
