// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The classic text tasks in a browser: the same public API as the native
// library, run by Google's official @mediapipe/tasks-text on a worker that
// mediapipe_flutter_text_web installs (text_task_backend.dart).

import 'dart:typed_data';

import 'package:mediapipe_flutter_core/interface.dart';
import 'package:mediapipe_flutter_core/mediapipe_flutter_core.dart';
import 'package:mediapipe_flutter_text/interface.dart';

import '../backend_text_task.dart';
import '../interface/embedding_gemma_types.dart' show TextEmbedding;

/// {@macro TextClassifier}
class TextClassifier extends BaseTextClassifier {
  /// Starts loading at once; initialization failures reach [classify].
  TextClassifier(TextClassifierOptions options)
    : _task = BackendTextTask.start(
        task: 'text_classifier',
        options: {
          ...backendModel(options.baseOptions),
          ...backendClassifierOptions(options.classifierOptions),
        },
        decode: TextClassifierResult._fromJs,
      );

  final BackendTextTask<TextClassifierResult> _task;

  /// Starts Google's browser Text Classifier.
  static Future<TextClassifier> create(TextClassifierOptions options) async {
    final task = TextClassifier(options);
    await task._task.ready;
    return task;
  }

  @override
  Future<TextClassifierResult> classify(String text) => _task.run(text);

  @override
  Future<void> dispose() => _task.dispose();
}

/// {@macro TextClassifierOptions}
// ignore: must_be_immutable
class TextClassifierOptions extends BaseTextClassifierOptions {
  /// Classifies with the model in [baseOptions].
  TextClassifierOptions({
    required BaseOptions baseOptions,
    this.classifierOptions = const ClassifierOptions(),
  }) : baseOptions = _checkedBaseOptions(baseOptions);

  /// {@macro TextClassifierOptions.fromAssetPath}
  ///
  /// In a browser the path is a URL, resolved against the page.
  factory TextClassifierOptions.fromAssetPath(
    String assetPath, {
    ClassifierOptions classifierOptions = const ClassifierOptions(),
  }) => TextClassifierOptions(
    baseOptions: BaseOptions.path(assetPath),
    classifierOptions: classifierOptions,
  );

  /// {@macro TextClassifierOptions.fromAssetBuffer}
  factory TextClassifierOptions.fromAssetBuffer(
    Uint8List assetBuffer, {
    ClassifierOptions classifierOptions = const ClassifierOptions(),
  }) => TextClassifierOptions(
    baseOptions: BaseOptions.memory(assetBuffer),
    classifierOptions: classifierOptions,
  );

  @override
  final BaseOptions baseOptions;

  @override
  final ClassifierOptions classifierOptions;
}

/// {@macro TextClassifierResult}
class TextClassifierResult extends BaseTextClassifierResult {
  /// {@macro TextClassifierResult.fake}
  TextClassifierResult({
    required Iterable<Classifications> classifications,
    this.timestampMs,
  }) : classifications = List.unmodifiable(classifications);

  factory TextClassifierResult._fromJs(Map<String, dynamic> json) =>
      TextClassifierResult(
        classifications: _heads(backendClassifications(json)),
        timestampMs: backendTimestamp(json),
      );

  @override
  final List<Classifications> classifications;

  /// Optional timestamp supplied by MediaPipe.
  final int? timestampMs;
}

/// {@macro TextEmbedder}
class TextEmbedder extends BaseTextEmbedder {
  /// Starts loading at once; initialization failures reach [embed].
  TextEmbedder(TextEmbedderOptions options)
    : _task = BackendTextTask.start(
        task: 'text_embedder',
        options: {
          ...backendModel(options.baseOptions),
          ...backendEmbedderOptions(options.embedderOptions),
        },
        decode: TextEmbedderResult._fromJs,
      );

  final BackendTextTask<TextEmbedderResult> _task;

  /// Starts Google's browser Text Embedder.
  static Future<TextEmbedder> create(TextEmbedderOptions options) async {
    final task = TextEmbedder(options);
    await task._task.ready;
    return task;
  }

  @override
  Future<TextEmbedderResult> embed(String text) => _task.run(text);

  @override
  Future<double> cosineSimilarity(BaseEmbedding a, BaseEmbedding b) async {
    _task.checkActive();
    TextEmbedding convert(BaseEmbedding value) => TextEmbedding(
      floatValues: value.isFloat ? value.floatEmbedding : null,
      quantizedValues: value.isQuantized ? value.quantizedEmbedding : null,
      headIndex: value.headIndex,
      headName: value.headName,
    );
    return TextEmbedding.cosineSimilarity(convert(a), convert(b));
  }

  @override
  Future<void> dispose() => _task.dispose();
}

/// {@macro TextEmbedderOptions}
// ignore: must_be_immutable
class TextEmbedderOptions extends BaseTextEmbedderOptions {
  /// Embeds with the model in [baseOptions].
  TextEmbedderOptions({
    required BaseOptions baseOptions,
    this.embedderOptions = const EmbedderOptions(),
  }) : baseOptions = _checkedBaseOptions(baseOptions);

  /// {@macro TextEmbedderOptions.fromAssetPath}
  ///
  /// In a browser the path is a URL, resolved against the page.
  factory TextEmbedderOptions.fromAssetPath(
    String assetPath, {
    EmbedderOptions embedderOptions = const EmbedderOptions(),
  }) => TextEmbedderOptions(
    baseOptions: BaseOptions.path(assetPath),
    embedderOptions: embedderOptions,
  );

  /// {@macro TextEmbedderOptions.fromAssetBuffer}
  factory TextEmbedderOptions.fromAssetBuffer(
    Uint8List assetBuffer, {
    EmbedderOptions embedderOptions = const EmbedderOptions(),
  }) => TextEmbedderOptions(
    baseOptions: BaseOptions.memory(assetBuffer),
    embedderOptions: embedderOptions,
  );

  @override
  final BaseOptions baseOptions;

  @override
  final EmbedderOptions embedderOptions;
}

/// {@macro TextEmbedderResult}
class TextEmbedderResult extends BaseEmbedderResult {
  /// {@macro TextEmbedderResult.fake}
  TextEmbedderResult({
    required Iterable<Embedding> embeddings,
    this.timestampMs,
  }) : embeddings = List.unmodifiable(embeddings);

  factory TextEmbedderResult._fromJs(Map<String, dynamic> json) =>
      TextEmbedderResult(
        embeddings: _embeddings(backendEmbeddings(json)),
        timestampMs: backendTimestamp(json),
      );

  @override
  final List<Embedding> embeddings;

  /// Optional timestamp supplied by MediaPipe.
  final int? timestampMs;
}

/// {@macro LanguageDetector}
class LanguageDetector extends BaseLanguageDetector {
  /// Starts loading at once; initialization failures reach [detect].
  LanguageDetector(LanguageDetectorOptions options)
    : _task = BackendTextTask.start(
        task: 'language_detector',
        options: {
          ...backendModel(options.baseOptions),
          ...backendClassifierOptions(options.classifierOptions),
        },
        decode: LanguageDetectorResult._fromJs,
      );

  final BackendTextTask<LanguageDetectorResult> _task;

  /// Starts Google's browser Language Detector.
  static Future<LanguageDetector> create(
    LanguageDetectorOptions options,
  ) async {
    final task = LanguageDetector(options);
    await task._task.ready;
    return task;
  }

  @override
  Future<LanguageDetectorResult> detect(String text) => _task.run(text);

  @override
  Future<void> dispose() => _task.dispose();
}

/// {@macro LanguageDetectorOptions}
class LanguageDetectorOptions extends BaseLanguageDetectorOptions {
  /// Detects with the model in [baseOptions].
  LanguageDetectorOptions({
    required BaseOptions baseOptions,
    this.classifierOptions = const ClassifierOptions(),
  }) : baseOptions = _checkedBaseOptions(baseOptions);

  /// {@macro LanguageDetectorOptions.fromAssetPath}
  ///
  /// In a browser the path is a URL, resolved against the page.
  factory LanguageDetectorOptions.fromAssetPath(
    String assetPath, {
    ClassifierOptions classifierOptions = const ClassifierOptions(),
  }) => LanguageDetectorOptions(
    baseOptions: BaseOptions.path(assetPath),
    classifierOptions: classifierOptions,
  );

  /// {@macro LanguageDetectorOptions.fromAssetBuffer}
  factory LanguageDetectorOptions.fromAssetBuffer(
    Uint8List assetBuffer, {
    ClassifierOptions classifierOptions = const ClassifierOptions(),
  }) => LanguageDetectorOptions(
    baseOptions: BaseOptions.memory(assetBuffer),
    classifierOptions: classifierOptions,
  );

  @override
  final BaseOptions baseOptions;

  @override
  final ClassifierOptions classifierOptions;
}

/// {@macro LanguageDetectorResult}
class LanguageDetectorResult extends BaseLanguageDetectorResult {
  /// {@macro LanguageDetectorResult.fake}
  LanguageDetectorResult({required Iterable<LanguagePrediction> predictions})
    : predictions = List.unmodifiable(predictions);

  factory LanguageDetectorResult._fromJs(Map<String, dynamic> json) =>
      LanguageDetectorResult(
        predictions: [
          for (final (code, probability) in backendLanguages(json))
            LanguagePrediction(languageCode: code, probability: probability),
        ],
      );

  @override
  final List<LanguagePrediction> predictions;
}

/// {@macro LanguagePrediction}
class LanguagePrediction extends BaseLanguagePrediction {
  /// {@macro LanguagePrediction}
  LanguagePrediction({required this.languageCode, required this.probability});

  @override
  final String languageCode;

  @override
  final double probability;
}

BaseOptions _checkedBaseOptions(BaseOptions value) {
  if (value.modelAssetPath case final path?) {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'modelAssetPath', 'Must not be empty.');
    }
    return BaseOptions.path(path);
  }
  final bytes = value.modelAssetBuffer;
  if (bytes == null || bytes.isEmpty) {
    throw ArgumentError('modelAssetBuffer must not be empty.');
  }
  return BaseOptions.memory(Uint8List.fromList(bytes).asUnmodifiableView());
}

List<Classifications> _heads(List<BackendHead> heads) => [
  for (final head in heads)
    Classifications(
      categories: [
        for (final c in head.categories)
          Category(
            index: c.index,
            score: c.score,
            categoryName: c.categoryName,
            displayName: c.displayName,
          ),
      ],
      headIndex: head.headIndex,
      headName: head.headName,
    ),
];

List<Embedding> _embeddings(List<BackendEmbedding> values) => [
  for (final e in values)
    if (e.floats case final floats?)
      Embedding.float(floats, headIndex: e.headIndex, headName: e.headName)
    else
      Embedding.quantized(
        e.quantized!,
        headIndex: e.headIndex,
        headName: e.headName,
      ),
];
