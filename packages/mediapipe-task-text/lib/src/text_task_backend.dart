/// The hook through which this package's platform code runs the text tasks
/// on Google's runtime for its platform: the classic tasks and EmbeddingGemma
/// on Google's browser runtime and Android SDK, and the Proofreader and
/// Summarizer on its Android SDK.
library;

/// One of Google's text tasks, created and run by a platform backend.
abstract interface class TextTaskBackend {
  /// Runs [text] with the request's [arguments], named as in Google's
  /// JavaScript API (the embedder's `formatContext`), and returns Google's
  /// result as JSON values.
  Future<Map<String, dynamic>> run(
    String text, [
    Map<String, Object?> arguments = const {},
  ]);

  /// Streams Google's updates for [text] as JSON values: each carries `done`,
  /// and the one with `done` true ends the stream. The stream starts on
  /// listen, has one subscription, and runs to Google's final update even
  /// after its listener cancels, since Google's generation cannot be
  /// cancelled.
  Stream<Map<String, dynamic>> stream(String text);

  /// Waits for queued requests, then closes Google's task.
  Future<void> dispose();
}

/// Creates Google's `task` (`text_classifier`, `text_embedder`,
/// `language_detector`, `text_proofreader` or `text_summarizer`) from
/// `options` named as in Google's JavaScript API, plus `modelBytes` (a
/// `Uint8List`) or `modelPath` (a URL in a browser, a file on Android).
///
/// Installed by this package's platform code in browsers and on Android;
/// null where the package runs Google's runtime itself.
Future<TextTaskBackend> Function(String task, Map<String, Object?> options)?
textTaskBackendFactory;
