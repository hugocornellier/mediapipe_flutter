/// The hook through which a platform plugin, such as
/// mediapipe_flutter_text_web, runs the classic text tasks (Text Classifier,
/// Text Embedder, Language Detector) on Google's runtime for its platform.
library;

/// One of Google's text tasks, created and run by a platform plugin.
abstract interface class TextTaskBackend {
  /// Runs [text] and returns Google's JavaScript result, as JSON values.
  Future<Map<String, dynamic>> run(String text);

  /// Waits for queued requests, then closes Google's task.
  Future<void> dispose();
}

/// Creates Google's [task] (`text_classifier`, `text_embedder` or
/// `language_detector`) from [options] named as in Google's JavaScript API,
/// plus `modelBytes` (a `Uint8List`) or `modelPath` (a URL in a browser).
///
/// Installed by a platform plugin (mediapipe_flutter_text_web in browsers);
/// null where the package runs Google's runtime itself.
Future<TextTaskBackend> Function(String task, Map<String, Object?> options)?
textTaskBackendFactory;
