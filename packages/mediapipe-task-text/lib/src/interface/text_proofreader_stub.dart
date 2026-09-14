import 'text_proofreader_types.dart';

/// Official Proofreader task; native implementation requires dart:io.
final class TextProofreader {
  TextProofreader._();

  /// Load an official model on a supported platform.
  static Future<TextProofreader> create(TextProofreaderOptions options) =>
      throw UnsupportedError('TextProofreader requires macOS arm64 CPU.');

  /// Selected inference backend.
  TextDelegate get delegate =>
      throw UnsupportedError('Native runtime required.');

  /// Return completed corrected text and native edits.
  Future<TextProofreaderResult> proofread(String text) =>
      throw UnsupportedError('Native runtime required.');

  /// Stream newly generated text and native corrections.
  Stream<TextProofreaderUpdate> proofreadStream(String text) =>
      throw UnsupportedError('Native runtime required.');

  /// Drain work and release the task.
  Future<void> dispose() => throw UnsupportedError('Native runtime required.');
}
