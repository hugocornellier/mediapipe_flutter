import 'package:mediapipe_core/mediapipe_exception.dart';

import '../../../capabilities.dart';
import '../interface/text_summarizer_types.dart';
import 'native_text_summarizer.dart';
import 'text_task_worker.dart';

/// Official MediaPipe Summarizer on a persistent worker isolate.
///
/// Enable `mediapipe_core.tasks_runtime: true` in app hook settings.
///
/// ```dart
/// final task = await TextSummarizer.create(
///   TextSummarizerOptions(model: TextModels.summarizer),
/// );
/// final result = await task.summarize('Long text');
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class TextSummarizer {
  TextSummarizer._(this.delegate, this.mode, this._worker);

  /// Backend fixed at creation.
  final TextDelegate delegate;

  /// Summarization mode fixed at creation; create another task to switch modes.
  final TextSummarizerMode mode;
  final TextTaskWorker<
    TextSummarizerResult,
    TextSummarizerUpdate,
    TextTaskException
  >
  _worker;

  /// Load the official model without blocking the calling isolate.
  static Future<TextSummarizer> create(TextSummarizerOptions options) async {
    await options.prepareModel();
    final support = await queryTextTaskCapabilities(TextTask.summarizer);
    if (support.unavailableReasons[options.delegate] case final reason?) {
      throw RuntimeUnavailableException(
        'TextSummarizer is unavailable on this platform.',
        fix: reason,
      );
    }
    return TextSummarizer._(
      options.delegate,
      options.mode,
      await TextTaskWorker.start(
        name: 'TextSummarizer',
        options: options,
        create: NativeTextSummarizer.new,
        exception: _exception,
      ),
    );
  }

  /// Return Google's completed summary without rewriting its text.
  Future<TextSummarizerResult> summarize(String text) => _worker.run(text);

  /// Stream new chunks and the terminal flag; starts on listen.
  ///
  /// One subscription. Cancellation suppresses delivery and waits for native
  /// completion because Google exposes no inference cancellation operation.
  /// Pausing buffers Dart events, without pausing generation.
  Stream<TextSummarizerUpdate> summarizeStream(String text) =>
      _worker.stream(text);

  /// Drain queued work and streams, then close the native task and worker once.
  Future<void> dispose() => _worker.dispose();
}

TextTaskException _exception(Object error) =>
    error is TextTaskException ? error : TextTaskException(error.toString());
