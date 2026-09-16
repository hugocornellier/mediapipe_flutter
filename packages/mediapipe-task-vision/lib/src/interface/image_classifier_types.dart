import 'vision_task_types.dart';
export 'vision_task_types.dart';

/// Configuration for the official Image Classifier.
final class ImageClassifierOptions extends VisionModelOptions {
  /// Defaults match the official task; allowlists and denylists are exclusive.
  ImageClassifierOptions({
    super.modelPath,
    super.modelBytes,
    super.runningMode,
    super.delegate,
    this.displayNamesLocale,
    this.maxResults = -1,
    this.scoreThreshold = 0.0,
    List<String>? categoryAllowlist,
    List<String>? categoryDenylist,
  }) : categoryAllowlist = List.unmodifiable(categoryAllowlist ?? const []),
       categoryDenylist = List.unmodifiable(categoryDenylist ?? const []) {
    if (maxResults == 0 ||
        maxResults < -0x80000000 ||
        maxResults > 0x7fffffff) {
      throw ArgumentError.value(
        maxResults,
        'maxResults',
        'Must be a nonzero C int',
      );
    }
    if (!scoreThreshold.isFinite) {
      throw ArgumentError.value(
        scoreThreshold,
        'scoreThreshold',
        'Must be finite',
      );
    }
    if (this.categoryAllowlist.isNotEmpty && this.categoryDenylist.isNotEmpty) {
      throw ArgumentError('Supply at most one category allowlist or denylist.');
    }
    for (final value in [
      ?displayNamesLocale,
      ...this.categoryAllowlist,
      ...this.categoryDenylist,
    ]) {
      if (value.isEmpty || value.contains('\u0000')) {
        throw ArgumentError.value(value, 'label', 'Invalid metadata label');
      }
    }
  }

  /// Locale of optional display labels in model metadata.
  final String? displayNamesLocale;

  /// Maximum categories per head; negative returns all categories.
  final int maxResults;

  /// Minimum returned prediction score.
  final double scoreThreshold;

  /// Categories to include; mutually exclusive with [categoryDenylist].
  final List<String> categoryAllowlist;

  /// Categories to exclude; mutually exclusive with [categoryAllowlist].
  final List<String> categoryDenylist;
}

/// Owned output from every classification head.
final class ImageClassifierResult {
  /// Store immutable results, valid after native teardown.
  ImageClassifierResult({
    required List<VisionClassifications> classifications,
    required this.imageWidth,
    required this.imageHeight,
    this.timestampMilliseconds,
  }) : classifications = List.unmodifiable(classifications);

  /// Classifications in the official task's order.
  final List<VisionClassifications> classifications;

  /// Decoded width of the input image.
  final int imageWidth;

  /// Decoded height of the input image.
  final int imageHeight;

  /// Input video timestamp, or null for a still image.
  final int? timestampMilliseconds;
}
