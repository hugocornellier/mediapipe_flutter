/// The hook through which mediapipe_flutter_text_web runs the classic text
/// tasks (Text Classifier, Text Embedder, Language Detector) in a browser.
library;

/// One of Google's browser text tasks, created and run on a worker.
abstract interface class TextWebTask {
  /// Runs [text] and returns Google's JavaScript result, as JSON values.
  Future<Map<String, dynamic>> run(String text);

  /// Waits for queued requests, then closes Google's task.
  Future<void> dispose();
}

/// Creates Google's [task] (`text_classifier`, `text_embedder` or
/// `language_detector`) from [options] named as in Google's JavaScript API,
/// plus `modelBytes` (a `Uint8List`) or `modelPath` (a URL).
///
/// Installed by the mediapipe_flutter_text_web plugin; null elsewhere.
Future<TextWebTask> Function(String task, Map<String, Object?> options)?
textWebTaskFactory;
