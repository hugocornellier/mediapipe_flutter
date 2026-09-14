import 'embedding_gemma_types.dart' show TextDelegate;
export 'embedding_gemma_types.dart' show TextDelegate;

/// Options passed to Google's official Proofreader pipeline.
final class TextProofreaderOptions {
  /// Load a `.litertlm` file. Prefer a file path for this large model.
  TextProofreaderOptions({
    required this.modelPath,
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

  /// Filesystem path to Google's model, not a Flutter asset key.
  final String modelPath;

  /// Input/output token budget. Null or zero selects Google's model default.
  final int? maxNumTokens;

  /// Optional native cache directory; null preserves Google's default.
  final String? cacheDirectory;

  /// CPU on macOS arm64. Unsupported backends fail without fallback.
  final TextDelegate delegate;
}

/// A correction type emitted by Google's diff implementation.
enum ProofreadingCorrectionType {
  /// Unchanged text.
  same,

  /// Inserted text.
  insertion,

  /// Deleted text.
  deletion,
}

/// One owned correction segment, preserved in Google's original order.
final class ProofreadingCorrection {
  /// Store a native correction without coalescing or recomputing the diff.
  const ProofreadingCorrection({required this.type, required this.text});

  /// Unchanged, inserted or deleted segment.
  final ProofreadingCorrectionType type;

  /// UTF-8 text decoded to a Dart string.
  final String text;
}

/// Completed, owned result. It remains valid after task disposal.
final class TextProofreaderResult {
  /// Preserve Google's corrected text and ordered correction segments.
  TextProofreaderResult({
    required this.proofreadText,
    required Iterable<ProofreadingCorrection> corrections,
  }) : corrections = List.unmodifiable(corrections);

  /// Corrected text; null is preserved if Google returns no text pointer.
  final String? proofreadText;

  /// Native correction segments. No result disposal is required.
  final List<ProofreadingCorrection> corrections;
}

/// One copied update from Google's native streaming callback.
final class TextProofreaderUpdate {
  /// Preserve the chunk, corrections and terminal flag exactly as delivered.
  TextProofreaderUpdate({
    required this.chunk,
    required this.done,
    required Iterable<ProofreadingCorrection> corrections,
  }) : corrections = List.unmodifiable(corrections);

  /// Newly generated text, not an accumulated snapshot. May be null on done.
  final String? chunk;

  /// Whether Google has completed this request.
  final bool done;

  /// Native correction segments, normally supplied by the final update.
  final List<ProofreadingCorrection> corrections;
}

/// Native inference, initialization, callback-copy or worker failure.
final class TextProofreaderException implements Exception {
  /// Preserve Google's message and status when available.
  const TextProofreaderException(this.message, {this.status});

  /// Description of the failure.
  final String message;

  /// Native status code, or null for a Dart/bridge failure.
  final int? status;

  @override
  String toString() =>
      'TextProofreaderException${status == null ? '' : ' ($status)'}: $message';
}
