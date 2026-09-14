/// Failure in a MediaPipe TextClassifier, TextEmbedder or LanguageDetector.
final class TextTaskException implements Exception {
  /// Google's error message and optional C API status.
  const TextTaskException(this.message, {this.status});

  /// Native or worker error description.
  final String message;

  /// Native status, when available.
  final int? status;

  @override
  String toString() =>
      'TextTaskException${status == null ? '' : ' ($status)'}: $message';
}
