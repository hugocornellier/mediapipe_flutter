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

import '../../text_task_backend.dart';
import '../interface/embedding_gemma_types.dart' show TextEmbedding;

/// {@macro TextClassifier}
class TextClassifier extends BaseTextClassifier {
  TextClassifier._(this._task);

  final _WebTextTask _task;

  /// Starts Google's browser Text Classifier.
  static Future<TextClassifier> create(TextClassifierOptions options) async =>
      TextClassifier._(
        await _WebTextTask.create('text_classifier', {
          ..._baseOptions(options.baseOptions),
          ..._classifierOptions(options.classifierOptions),
        }),
      );

  @override
  Future<TextClassifierResult> classify(String text) async =>
      TextClassifierResult._fromJs(await _task.run(text));

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
        classifications: [
          for (final head in json['classifications'] as List)
            _classifications(head as Map<String, dynamic>),
        ],
        timestampMs: (json['timestampMs'] as num?)?.toInt(),
      );

  @override
  final List<Classifications> classifications;

  /// Optional timestamp supplied by MediaPipe.
  final int? timestampMs;
}

/// {@macro TextEmbedder}
class TextEmbedder extends BaseTextEmbedder {
  TextEmbedder._(this._task);

  final _WebTextTask _task;

  /// Starts Google's browser Text Embedder.
  static Future<TextEmbedder> create(TextEmbedderOptions options) async =>
      TextEmbedder._(
        await _WebTextTask.create('text_embedder', {
          ..._baseOptions(options.baseOptions),
          'l2Normalize': options.embedderOptions.l2Normalize,
          'quantize': options.embedderOptions.quantize,
        }),
      );

  @override
  Future<TextEmbedderResult> embed(String text) async =>
      TextEmbedderResult._fromJs(await _task.run(text));

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
        embeddings: [
          for (final value in json['embeddings'] as List)
            _embedding(value as Map<String, dynamic>),
        ],
        timestampMs: (json['timestampMs'] as num?)?.toInt(),
      );

  @override
  final List<Embedding> embeddings;

  /// Optional timestamp supplied by MediaPipe.
  final int? timestampMs;
}

/// {@macro LanguageDetector}
class LanguageDetector extends BaseLanguageDetector {
  LanguageDetector._(this._task);

  final _WebTextTask _task;

  /// Starts Google's browser Language Detector.
  static Future<LanguageDetector> create(
    LanguageDetectorOptions options,
  ) async => LanguageDetector._(
    await _WebTextTask.create('language_detector', {
      ..._baseOptions(options.baseOptions),
      ..._classifierOptions(options.classifierOptions),
    }),
  );

  @override
  Future<LanguageDetectorResult> detect(String text) async =>
      LanguageDetectorResult._fromJs(await _task.run(text));

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
          for (final value in json['languages'] as List)
            LanguagePrediction(
              languageCode: (value as Map)['languageCode'] as String,
              probability: (value['probability'] as num).toDouble(),
            ),
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

/// Lifecycle shared by the three tasks, matching the native library: requests
/// run in order, and none is accepted once disposal begins.
final class _WebTextTask {
  _WebTextTask._(this._task);

  final TextTaskBackend _task;
  Future<void>? _disposing;

  static Future<_WebTextTask> create(
    String task,
    Map<String, Object?> options,
  ) async {
    final factory = textTaskBackendFactory;
    if (factory == null) {
      throw UnsupportedError(
        'Text tasks in a browser need the mediapipe_flutter_text_web '
        'package; add it to the app.',
      );
    }
    try {
      return _WebTextTask._(await factory(task, options));
    } on TextTaskException {
      rethrow;
    } catch (error) {
      throw TextTaskException('$error');
    }
  }

  void checkActive() {
    if (_disposing != null) throw StateError('Text task has been disposed.');
  }

  Future<Map<String, dynamic>> run(String text) async {
    checkActive();
    if (text.contains('\u0000')) {
      throw ArgumentError('Text must not contain NUL.');
    }
    try {
      return await _task.run(text);
    } on TextTaskException {
      rethrow;
    } catch (error) {
      throw TextTaskException('$error');
    }
  }

  Future<void> dispose() => _disposing ??= _task.dispose();
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

Map<String, Object?> _baseOptions(BaseOptions value) => {
  'modelBytes': value.modelAssetBuffer,
  'modelPath': value.modelAssetPath == null
      ? null
      : Uri.base.resolve(value.modelAssetPath!).toString(),
};

Map<String, Object?> _classifierOptions(ClassifierOptions value) => {
  'displayNamesLocale': ?value.displayNamesLocale,
  'maxResults': ?value.maxResults,
  'scoreThreshold': ?value.scoreThreshold,
  'categoryAllowlist': ?value.categoryAllowlist,
  'categoryDenylist': ?value.categoryDenylist,
};

Classifications _classifications(Map<String, dynamic> head) => Classifications(
  categories: [
    for (final value in head['categories'] as List)
      Category(
        index: ((value as Map)['index'] as num).toInt(),
        score: (value['score'] as num).toDouble(),
        categoryName: _name(value['categoryName']),
        displayName: _name(value['displayName']),
      ),
  ],
  headIndex: (head['headIndex'] as num).toInt(),
  headName: _name(head['headName']),
);

Embedding _embedding(Map<String, dynamic> value) {
  final headIndex = (value['headIndex'] as num).toInt();
  final headName = _name(value['headName']);
  if (value['floatEmbedding'] case final List floats?) {
    return Embedding.float(
      Float32List.fromList([for (final v in floats) (v as num).toDouble()]),
      headIndex: headIndex,
      headName: headName,
    );
  }
  return Embedding.quantized(
    Uint8List.fromList([
      for (final v in value['quantizedEmbedding'] as List) (v as num).toInt(),
    ]),
    headIndex: headIndex,
    headName: headName,
  );
}

// Google's JavaScript results use empty strings where the native API has
// no value.
String? _name(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
