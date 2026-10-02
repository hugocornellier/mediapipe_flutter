/// Google's native text runtime: each task on its own worker isolate.
library;

import '../runner/text_task_runner.dart';
import '../types/options.dart';
import '../types/results.dart';
import 'classic_text_runtime.dart';
import 'native_language_detector.dart';
import 'native_text_classifier.dart';
import 'native_text_embedder.dart';
import 'native_text_proofreader.dart';
import 'native_text_summarizer.dart';
import 'text_task_worker.dart';

/// Opens Google's Text Classifier on a worker.
Future<TextTaskRunner<String, TextClassifierResult>> openNativeTextClassifier(
  TextClassifierOptions options,
) {
  requireTextTasksRuntime();
  return TextTaskWorker.start(
    name: 'TextClassifier',
    options: options,
    create: NativeTextClassifier.new,
  );
}

/// Opens Google's Language Detector on a worker.
Future<TextTaskRunner<String, LanguageDetectorResult>>
openNativeLanguageDetector(LanguageDetectorOptions options) {
  requireTextTasksRuntime();
  return TextTaskWorker.start(
    name: 'LanguageDetector',
    options: options,
    create: NativeLanguageDetector.new,
  );
}

/// Opens Google's Text Embedder on a worker.
Future<TextTaskRunner<TextEmbedderInput, TextEmbedderResult>>
openNativeTextEmbedder(TextEmbedderOptions options) {
  requireTextTasksRuntime();
  return TextTaskWorker.start(
    name: 'TextEmbedder',
    options: options,
    create: NativeTextEmbedder.new,
  );
}

/// Opens Google's Proofreader on a worker.
Future<TextStreamRunner<String, TextProofreaderResult, TextProofreaderUpdate>>
openNativeTextProofreader(TextProofreaderOptions options) {
  requireTextTasksRuntime();
  return TextTaskWorker.start(
    name: 'TextProofreader',
    options: options,
    create: NativeTextProofreader.new,
  );
}

/// Opens Google's Summarizer on a worker.
Future<TextStreamRunner<String, TextSummarizerResult, TextSummarizerUpdate>>
openNativeTextSummarizer(TextSummarizerOptions options) {
  requireTextTasksRuntime();
  return TextTaskWorker.start(
    name: 'TextSummarizer',
    options: options,
    create: NativeTextSummarizer.new,
  );
}
