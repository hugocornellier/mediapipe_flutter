/// Failures reported by MediaPipe tasks and model loading.
library;

/// A failure from MediaPipe or its supporting runtime.
///
/// Catch it for every MediaPipe failure. Its subtypes separate a platform or
/// setup that cannot run the task ([RuntimeUnavailableException]), a model
/// that could not be downloaded (`ModelDownloadException`), and a task that
/// failed in native code (each family's `VisionTaskException`,
/// `TextTaskException` or `AudioTaskException`). Programming errors such as
/// invalid options and use after disposal remain [ArgumentError] and
/// [StateError].
class MediaPipeException implements Exception {
  /// Creates a failure with a human-readable [message] and optional [cause].
  const MediaPipeException(this.message, {this.cause});

  /// A description suitable for logs or an error message.
  final String message;

  /// The original failure, if one was available.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// The platform cannot load a task runtime required by this operation.
final class RuntimeUnavailableException extends MediaPipeException {
  /// Creates a runtime failure with actionable [fix] text.
  const RuntimeUnavailableException(
    super.message, {
    required this.fix,
    super.cause,
  });

  /// The setup change needed to make the runtime available.
  final String fix;

  @override
  String toString() => '$runtimeType: $message $fix';
}
