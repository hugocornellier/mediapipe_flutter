import 'package:mediapipe_core/mediapipe_exception.dart';

import 'text_proofreader_types.dart';

/// Official Proofreader task; native implementation requires dart:io.
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
  TextProofreader._();

  /// Load an official model on a supported platform.
  static Future<TextProofreader> create(TextProofreaderOptions options) =>
      throw const RuntimeUnavailableException(
        'TextProofreader is unavailable on this platform.',
        fix: 'Use macOS arm64 CPU, macOS 14 or later.',
      );

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
