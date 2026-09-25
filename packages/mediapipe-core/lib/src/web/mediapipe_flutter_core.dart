// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Browser containers and options: plain Dart values, with the io library's
// public constructors, that the web task adapters fill from Google's
// JavaScript results.

import 'dart:typed_data';

import 'package:mediapipe_flutter_core/interface.dart';

/// {@macro ClassifierResult}
class ClassifierResult extends BaseClassifierResult {
  /// {@macro ClassifierResult.fake}
  ClassifierResult({required Iterable<Classifications> classifications})
    : classifications = List.unmodifiable(classifications);

  @override
  final List<Classifications> classifications;
}

/// {@macro Category}
class Category extends BaseCategory {
  /// {@macro Category.fake}
  Category({
    required this.index,
    required this.score,
    required this.categoryName,
    required this.displayName,
  });

  @override
  final int index;

  @override
  final double score;

  @override
  final String? categoryName;

  @override
  final String? displayName;
}

/// {@macro Classifications}
class Classifications extends BaseClassifications {
  /// {@macro Classifications.fake}
  Classifications({
    required Iterable<Category> categories,
    required this.headIndex,
    required this.headName,
  }) : categories = List.unmodifiable(categories);

  @override
  final List<Category> categories;

  @override
  final int headIndex;

  @override
  final String? headName;
}

/// {@macro Embedding}
class Embedding extends BaseEmbedding {
  /// {@macro Embedding.fakeQuantized}
  Embedding.quantized(
    Uint8List this.quantizedEmbedding, {
    required this.headIndex,
    this.headName,
  }) : floatEmbedding = null,
       type = EmbeddingType.quantized;

  /// {@macro Embedding.fakeFloat}
  Embedding.float(
    Float32List this.floatEmbedding, {
    required this.headIndex,
    this.headName,
  }) : quantizedEmbedding = null,
       type = EmbeddingType.float;

  @override
  final EmbeddingType type;

  @override
  final int headIndex;

  @override
  final String? headName;

  @override
  final Uint8List? quantizedEmbedding;

  @override
  final Float32List? floatEmbedding;

  @override
  int get length => switch (type) {
    EmbeddingType.float => floatEmbedding!.length,
    EmbeddingType.quantized => quantizedEmbedding!.length,
  };
}

/// {@macro BaseOptions}
class BaseOptions extends BaseBaseOptions {
  const BaseOptions._({
    this.modelAssetBuffer,
    this.modelAssetPath,
    required this.type,
  });

  /// {@macro BaseOptions.path}
  ///
  /// In a browser the path is a URL, resolved against the page.
  factory BaseOptions.path(String path) =>
      BaseOptions._(modelAssetPath: path, type: BaseOptionsType.path);

  /// {@macro BaseOptions.memory}
  factory BaseOptions.memory(Uint8List buffer) =>
      BaseOptions._(modelAssetBuffer: buffer, type: BaseOptionsType.memory);

  @override
  final Uint8List? modelAssetBuffer;

  @override
  final String? modelAssetPath;

  @override
  final BaseOptionsType type;
}

/// {@macro ClassifierOptions}
class ClassifierOptions extends BaseClassifierOptions {
  /// {@macro ClassifierOptions}
  const ClassifierOptions({
    this.displayNamesLocale,
    this.maxResults,
    this.scoreThreshold,
    this.categoryAllowlist,
    this.categoryDenylist,
  });

  @override
  final String? displayNamesLocale;

  @override
  final int? maxResults;

  @override
  final double? scoreThreshold;

  @override
  final List<String>? categoryAllowlist;

  @override
  final List<String>? categoryDenylist;
}

/// {@macro EmbedderOptions}
class EmbedderOptions extends BaseEmbedderOptions {
  /// {@macro EmbedderOptions}
  const EmbedderOptions({this.l2Normalize = false, this.quantize = false});

  @override
  final bool l2Normalize;

  @override
  final bool quantize;
}
