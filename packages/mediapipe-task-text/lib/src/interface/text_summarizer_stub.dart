import 'package:mediapipe_core/mediapipe_exception.dart';

import 'text_summarizer_types.dart';

/// Official Summarizer; the native implementation requires dart:io.
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
  TextSummarizer._();

  /// Load an official model on a supported platform.
  static Future<TextSummarizer> create(TextSummarizerOptions options) =>
      throw const RuntimeUnavailableException(
        'TextSummarizer is unavailable on this platform.',
        fix: 'Use macOS arm64 CPU, macOS 14 or later.',
      );

  /// Selected backend.
  TextDelegate get delegate =>
      throw UnsupportedError('Native runtime required.');

  /// Selected summarization mode.
  TextSummarizerMode get mode =>
      throw UnsupportedError('Native runtime required.');

  /// Return the completed summary.
  Future<TextSummarizerResult> summarize(String text) =>
      throw UnsupportedError('Native runtime required.');

  /// Stream newly generated text and completion.
  Stream<TextSummarizerUpdate> summarizeStream(String text) =>
      throw UnsupportedError('Native runtime required.');

  /// Drain work and release the task.
  Future<void> dispose() => throw UnsupportedError('Native runtime required.');
}
