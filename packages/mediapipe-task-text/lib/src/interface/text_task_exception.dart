import 'package:mediapipe_core/mediapipe_exception.dart';

/// Failure in a MediaPipe text task: the classic classifier, embedder and
/// language detector, EmbeddingGemma, Proofreader and Summarizer.
final class TextTaskException extends MediaPipeException {
  /// Google's error message and optional native status code.
  const TextTaskException(super.message, {this.statusCode});

  /// MediaPipe/Abseil status code, when the failure came from native code.
  final int? statusCode;

  @override
  String toString() =>
      'TextTaskException${statusCode == null ? '' : ' ($statusCode)'}: '
      '$message';
}
