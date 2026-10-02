/// Browsers have no native runtime: the classic tasks and EmbeddingGemma run
/// through the registered browser plugin, so reaching these means it did not
/// register, and the generative tasks' capability queries refuse browsers
/// first (upstream-issues.md UP-034).
library;

import 'package:mediapipe_core/mediapipe_core.dart';

import '../types/options.dart';
import '../types/results.dart';
import 'text_task_runner.dart';

Never _unavailable() => throw const RuntimeUnavailableException(
  'The MediaPipe text browser plugin did not register.',
  fix:
      'Depend on mediapipe_text as a Flutter plugin so its web '
      'registration runs before the first task is created.',
);

/// The native Text Classifier; browsers have none.
Future<TextTaskRunner<String, TextClassifierResult>> openNativeTextClassifier(
  TextClassifierOptions options,
) async => _unavailable();

/// The native Language Detector; browsers have none.
Future<TextTaskRunner<String, LanguageDetectorResult>>
openNativeLanguageDetector(LanguageDetectorOptions options) async =>
    _unavailable();

/// The native Text Embedder; browsers have none.
Future<TextTaskRunner<TextEmbedderInput, TextEmbedderResult>>
openNativeTextEmbedder(TextEmbedderOptions options) async => _unavailable();

/// The native Proofreader; browsers have none.
Future<TextStreamRunner<String, TextProofreaderResult, TextProofreaderUpdate>>
openNativeTextProofreader(TextProofreaderOptions options) async =>
    _unavailable();

/// The native Summarizer; browsers have none.
Future<TextStreamRunner<String, TextSummarizerResult, TextSummarizerUpdate>>
openNativeTextSummarizer(TextSummarizerOptions options) async => _unavailable();
