import 'text_summarizer_types.dart';

/// Official Summarizer; the native implementation requires dart:io.
final class TextSummarizer {
  TextSummarizer._();

  /// Load an official model on a supported platform.
  static Future<TextSummarizer> create(TextSummarizerOptions options) =>
      throw UnsupportedError('TextSummarizer requires macOS arm64 CPU.');

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
