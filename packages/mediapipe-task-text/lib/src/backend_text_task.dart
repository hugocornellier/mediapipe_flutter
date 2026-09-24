// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The classic text tasks through a platform plugin's backend
// (text_task_backend.dart): Google's browser runtime, or its Android or iOS
// SDK. Options travel named as in Google's JavaScript API and results come
// back as its JSON, decoded here into the package's own types.

import 'dart:typed_data';

import 'package:mediapipe_flutter_core/interface.dart';

import '../text_task_backend.dart';
import 'interface/text_task_exception.dart';

/// What the task classes need from the runtime running them: the native
/// worker (PendingTextTask) or a platform plugin's backend (BackendTextTask).
abstract interface class TextTaskRunner<R> {
  /// Completes once the task exists; throws its creation error.
  Future<void> get ready;

  /// Runs [text] after every request submitted before it.
  Future<R> run(String text);

  /// Rejects requests once disposal has begun.
  void checkActive();

  /// Waits for accepted requests, then closes the task.
  Future<void> dispose();
}

/// One text task on a registered backend, with the native library's
/// lifecycle: it starts loading at once, requests run in submission order,
/// and none is accepted once disposal begins.
final class BackendTextTask<R> implements TextTaskRunner<R> {
  BackendTextTask._(this._ready, this._decode);

  /// Starts Google's [task] on the registered backend with [options].
  factory BackendTextTask.start({
    required String task,
    required Map<String, Object?> options,
    required R Function(Map<String, dynamic> json) decode,
  }) {
    final factory =
        textTaskBackendFactory ??
        (throw UnsupportedError(
          'Text tasks here run through a platform plugin that is missing: '
          'add mediapipe_flutter_text_web for browsers, or '
          'mediapipe_flutter_text_android or mediapipe_flutter_text_ios for '
          'mobile.',
        ));
    final ready = Future(
      () => factory(task, options),
    ).catchError((Object error) => throw _exception(error));
    // A constructor cannot return a Future. Keep an early failure handled
    // until a caller awaits ready, a request or disposal.
    ready.ignore();
    return BackendTextTask._(ready, decode);
  }

  final Future<TextTaskBackend> _ready;
  final R Function(Map<String, dynamic> json) _decode;
  Future<void>? _disposing;
  Future<void> _tail = Future.value();

  /// Completes once Google's task exists; throws its creation error.
  @override
  Future<void> get ready async {
    await _ready;
  }

  /// Rejects requests once disposal has begun.
  @override
  void checkActive() {
    if (_disposing != null) throw StateError('Text task has been disposed.');
  }

  /// Runs [text] after every request submitted before it.
  @override
  Future<R> run(String text) {
    checkActive();
    if (text.contains('\u0000')) {
      throw ArgumentError('Text must not contain NUL.');
    }
    final result = _tail.then((_) async {
      try {
        return _decode(await (await _ready).run(text));
      } catch (error) {
        throw _exception(error);
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Waits for accepted requests, then closes Google's task.
  @override
  Future<void> dispose() => _disposing ??= _tail.then((_) async {
    final TextTaskBackend backend;
    try {
      backend = await _ready;
    } catch (_) {
      return;
    }
    await backend.dispose();
  });
}

TextTaskException _exception(Object error) =>
    error is TextTaskException ? error : TextTaskException('$error');

/// The model, as the backend reads it: `modelBytes` or `modelPath`.
Map<String, Object?> backendModel(BaseBaseOptions value) => {
  'modelBytes': value.modelAssetBuffer,
  'modelPath': value.modelAssetPath,
};

/// Classifier options named as in Google's JavaScript API.
Map<String, Object?> backendClassifierOptions(BaseClassifierOptions value) => {
  'displayNamesLocale': ?value.displayNamesLocale,
  'maxResults': ?value.maxResults,
  'scoreThreshold': ?value.scoreThreshold,
  'categoryAllowlist': ?value.categoryAllowlist,
  'categoryDenylist': ?value.categoryDenylist,
};

/// Embedder options named as in Google's JavaScript API.
Map<String, Object?> backendEmbedderOptions(BaseEmbedderOptions value) => {
  'l2Normalize': value.l2Normalize,
  'quantize': value.quantize,
};

/// A result's optional timestamp.
int? backendTimestamp(Map<String, dynamic> json) =>
    (json['timestampMs'] as num?)?.toInt();

/// One category of a classification head, as the platform's types take it.
typedef BackendCategory = ({
  int index,
  double score,
  String? categoryName,
  String? displayName,
});

/// One classification head.
typedef BackendHead = ({
  List<BackendCategory> categories,
  int headIndex,
  String? headName,
});

/// One embedding: exactly one of [floats] and [quantized] is set.
typedef BackendEmbedding = ({
  Float32List? floats,
  Uint8List? quantized,
  int headIndex,
  String? headName,
});

/// The classification heads of a Text Classifier or Language Detector result.
List<BackendHead> backendClassifications(Map<String, dynamic> json) => [
  for (final head in json['classifications'] as List)
    (
      categories: [
        for (final value in (head as Map)['categories'] as List)
          (
            index: ((value as Map)['index'] as num).toInt(),
            score: (value['score'] as num).toDouble(),
            categoryName: _name(value['categoryName']),
            displayName: _name(value['displayName']),
          ),
      ],
      headIndex: (head['headIndex'] as num).toInt(),
      headName: _name(head['headName']),
    ),
];

/// The embeddings of a Text Embedder result.
List<BackendEmbedding> backendEmbeddings(Map<String, dynamic> json) => [
  for (final raw in json['embeddings'] as List)
    if (raw case final Map value)
      (
        floats: switch (value['floatEmbedding']) {
          final List floats => Float32List.fromList([
            for (final v in floats) (v as num).toDouble(),
          ]),
          _ => null,
        },
        quantized: switch (value['floatEmbedding']) {
          List _ => null,
          _ => Uint8List.fromList([
            for (final v in value['quantizedEmbedding'] as List)
              (v as num).toInt(),
          ]),
        },
        headIndex: (value['headIndex'] as num).toInt(),
        headName: _name(value['headName']),
      ),
];

/// A Language Detector result's (language code, probability) pairs.
List<(String, double)> backendLanguages(Map<String, dynamic> json) => [
  for (final value in json['languages'] as List)
    (
      (value as Map)['languageCode'] as String,
      (value['probability'] as num).toDouble(),
    ),
];

// Google's JavaScript and SDK results use empty strings where the native API
// has no value.
String? _name(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
