import 'embedding_gemma_types.dart' show TextDelegate;
export 'embedding_gemma_types.dart' show TextDelegate;
import 'package:mediapipe_core/model_store.dart';
import 'package:mediapipe_core/platform_interface.dart';

import '../../models.dart' show TextModels;
export 'text_task_exception.dart' show TextTaskException;

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
    this.model,
    String? modelPath,
    this.mode = TextSummarizerMode.keypoints,
    this.maxNumTokens,
    this.cacheDirectory,
    this.delegate = TextDelegate.cpu,
  }) : _modelPath = modelPath {
    if ((model == null) == (modelPath == null)) {
      throw ArgumentError('Supply exactly one of model and modelPath.');
    }
    if (modelPath != null &&
        (modelPath.isEmpty || modelPath.contains('\u0000'))) {
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

  /// Pinned official model: the app's bundled copy, or a download when
  /// `ModelStore.allowDownloads` is true. Verified against its SHA-256.
  final DownloadAsset? model;

  final String? _modelPath;
  String? _resolvedPath;

  /// Resolves a pinned model before this task is passed to the runtime.
  Future<void> prepareModel() => _resolveModel();

  Future<void> _resolveModel() async {
    if (model case final selected?) {
      _resolvedPath = (await resolvePinnedModel(
        selected,
        family: 'mediapipe_text',
        registry: TextModels.byName,
      )).path;
    }
  }

  /// Filesystem path, not a Flutter asset key.
  String get modelPath => _resolvedPath ?? _modelPath!;

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
