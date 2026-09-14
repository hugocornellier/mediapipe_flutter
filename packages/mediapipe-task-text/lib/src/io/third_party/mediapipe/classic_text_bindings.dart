// Copyright 2026 The MediaPipe Authors. Licensed under Apache 2.0.
// Adapted from mediapipe==1.0.1 Python ctypes text_classifier.py,
// language_detector.py and components/containers/classification_result_c.py.
// ignore_for_file: public_member_api_docs
import 'dart:ffi';
import 'embedding_gemma_bindings.dart' show MpBaseOptions;
export 'embedding_gemma_bindings.dart' show MpBaseOptions, errorFree;

const _asset = 'package:mediapipe_flutter_core/tasks_1_0_1.dylib';

final class MpClassifierOptions extends Struct {
  external Pointer<Char> displayNamesLocale;
  @Int32()
  external int maxResults;
  @Float()
  external double scoreThreshold;
  external Pointer<Pointer<Char>> categoryAllowlist;
  @Uint32()
  external int categoryAllowlistCount;
  external Pointer<Pointer<Char>> categoryDenylist;
  @Uint32()
  external int categoryDenylistCount;
}

/// Identical layout for TextClassifierOptions and LanguageDetectorOptions.
final class MpTextClassifierOptions extends Struct {
  external MpBaseOptions baseOptions;
  external MpClassifierOptions classifierOptions;
}

final class MpCategory extends Struct {
  @Int32()
  external int index;
  @Float()
  external double score;
  external Pointer<Char> categoryName;
  external Pointer<Char> displayName;
}

final class MpClassifications extends Struct {
  external Pointer<MpCategory> categories;
  @Uint32()
  external int categoriesCount;
  @Int32()
  external int headIndex;
  external Pointer<Char> headName;
}

final class MpClassificationResult extends Struct {
  external Pointer<MpClassifications> classifications;
  @Uint32()
  external int classificationsCount;
  @Int64()
  external int timestampMs;
  @Bool()
  external bool hasTimestampMs;
}

final class MpLanguagePrediction extends Struct {
  external Pointer<Char> languageCode;
  @Float()
  external double probability;
}

final class MpLanguageDetectorResult extends Struct {
  external Pointer<MpLanguagePrediction> predictions;
  @Uint32()
  external int predictionsCount;
}

@Native<
  Int32 Function(
    Pointer<MpTextClassifierOptions>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpTextClassifierCreate', assetId: _asset)
external int classifierCreate(
  Pointer<MpTextClassifierOptions> options,
  Pointer<Pointer<Void>> task,
  Pointer<Pointer<Char>> error,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Char>,
    Pointer<MpClassificationResult>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpTextClassifierClassify', assetId: _asset)
external int classifierRun(
  Pointer<Void> task,
  Pointer<Char> text,
  Pointer<MpClassificationResult> result,
  Pointer<Pointer<Char>> error,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Pointer<Char>>)>(
  symbol: 'MpTextClassifierClose',
  assetId: _asset,
)
external int classifierClose(Pointer<Void> task, Pointer<Pointer<Char>> error);

@Native<Void Function(Pointer<MpClassificationResult>)>(
  symbol: 'MpTextClassifierCloseResult',
  assetId: _asset,
)
external void classifierCloseResult(Pointer<MpClassificationResult> result);

@Native<
  Int32 Function(
    Pointer<MpTextClassifierOptions>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpLanguageDetectorCreate', assetId: _asset)
external int languageCreate(
  Pointer<MpTextClassifierOptions> options,
  Pointer<Pointer<Void>> task,
  Pointer<Pointer<Char>> error,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Char>,
    Pointer<MpLanguageDetectorResult>,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'MpLanguageDetectorDetect', assetId: _asset)
external int languageRun(
  Pointer<Void> task,
  Pointer<Char> text,
  Pointer<MpLanguageDetectorResult> result,
  Pointer<Pointer<Char>> error,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Pointer<Char>>)>(
  symbol: 'MpLanguageDetectorClose',
  assetId: _asset,
)
external int languageClose(Pointer<Void> task, Pointer<Pointer<Char>> error);

@Native<Void Function(Pointer<MpLanguageDetectorResult>)>(
  symbol: 'MpLanguageDetectorCloseResult',
  assetId: _asset,
)
external void languageCloseResult(Pointer<MpLanguageDetectorResult> result);
