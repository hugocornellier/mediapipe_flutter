import 'embedding_gemma_types.dart' show TextDelegate;
export 'embedding_gemma_types.dart' show TextDelegate;

/// Summarization modes passed directly to Google's task pipeline.
enum TextSummarizerMode {
  /// A short summary paragraph.
  tldr,

  /// A bulleted list of key points; Google's default.
  keypoints,
}

/// Options for Google's official Summarization 200M task.
final class TextSummarizerOptions {
  /// Load a local `.litertlm` file; mode is fixed for this task's lifetime.
  TextSummarizerOptions({
    required this.modelPath,
    this.mode = TextSummarizerMode.keypoints,
    this.maxNumTokens,
    this.cacheDirectory,
    this.delegate = TextDelegate.cpu,
  }) {
    if (modelPath.isEmpty || modelPath.contains('\u0000')) {
      throw ArgumentError.value(
        modelPath,
        'modelPath',
        'Expected a nonempty path without NUL.',
      );
    }
    if (maxNumTokens != null &&
        (maxNumTokens! < 0 || maxNumTokens! > 0x7fffffff)) {
      throw ArgumentError.value(
        maxNumTokens,
        'maxNumTokens',
        'Must fit a nonnegative int32.',
      );
    }
    if (cacheDirectory != null &&
        (cacheDirectory!.isEmpty || cacheDirectory!.contains('\u0000'))) {
      throw ArgumentError.value(
        cacheDirectory,
        'cacheDirectory',
        'Expected a nonempty path without NUL.',
      );
    }
  }

  /// Filesystem path, not a Flutter asset key.
  final String modelPath;

  /// Paragraph or key-points mode; no custom prompts are added by Dart.
  final TextSummarizerMode mode;

  /// Input/output token budget; null or zero preserves Google's default.
  final int? maxNumTokens;

  /// Optional native cache directory; null preserves Google's default.
  final String? cacheDirectory;

  /// CPU on macOS arm64. Unsupported backends fail without fallback.
  final TextDelegate delegate;
}

/// Owned completed summary, valid after task disposal.
final class TextSummarizerResult {
  /// Preserve Google's completed text, including whitespace and bullet markers.
  const TextSummarizerResult({required this.summary});

  /// Native output, null if Google returned no text pointer.
  final String? summary;
}

/// One owned streaming update from Google's callback.
final class TextSummarizerUpdate {
  /// Store the new text chunk and native terminal flag.
  const TextSummarizerUpdate({required this.chunk, required this.done});

  /// Newly generated text, not accumulated output; may be null on completion.
  final String? chunk;

  /// Whether Google has finished this request.
  final bool done;
}

/// Native initialization, inference, callback-copy or worker failure.
final class TextSummarizerException implements Exception {
  /// Preserve the native message and status when available.
  const TextSummarizerException(this.message, {this.status});

  /// Failure description.
  final String message;

  /// Native status, or null for a Dart/bridge failure.
  final int? status;

  @override
  String toString() =>
      'TextSummarizerException${status == null ? '' : ' ($status)'}: $message';
}
