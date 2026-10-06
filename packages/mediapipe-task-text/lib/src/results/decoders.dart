/// One decoder from the platform SDK adapters' results to the Dart types.
///
/// Google's browser runtime and its Android SDK both deliver text results as
/// JSON in the shape of Google's JavaScript API; the adapters only forward
/// them, and every value is read here. The Proofreader and Summarizer, which
/// only the Android SDK serves this way, arrive with the names of its Java
/// getters.
library;

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart'
    show decodeClassifications, decodeEmbedding;

import '../types/results.dart';

/// Decodes a Text Classifier result.
TextClassifierResult decodeTextClassifierResult(Map<String, dynamic> json) =>
    TextClassifierResult(
      classifications: _classifications(json),
      timestampMilliseconds: _timestamp(json),
    );

/// Decodes a Text Embedder result.
TextEmbedderResult decodeTextEmbedderResult(Map<String, dynamic> json) =>
    TextEmbedderResult(
      timestampMilliseconds: _timestamp(json),
      embeddings: [
        for (final head in (json['embeddings'] as List).cast<Map>())
          decodeEmbedding(head),
      ],
    );

/// Decodes a Language Detector result.
LanguageDetectorResult decodeLanguageDetectorResult(
  Map<String, dynamic> json,
) => LanguageDetectorResult(
  predictions: [
    for (final value in (json['languages'] as List).cast<Map>())
      LanguagePrediction(
        languageCode: value['languageCode'] as String,
        probability: (value['probability'] as num).toDouble(),
      ),
  ],
);

/// Decodes a completed Proofreader result.
TextProofreaderResult decodeTextProofreaderResult(Map<String, dynamic> json) =>
    TextProofreaderResult(
      proofreadText: json['proofreadText'] as String?,
      corrections: _corrections(json['corrections']),
    );

/// Decodes one streamed Proofreader update.
TextProofreaderUpdate decodeTextProofreaderUpdate(Map<String, dynamic> json) =>
    TextProofreaderUpdate(
      chunk: json['chunk'] as String?,
      done: json['done'] == true,
      corrections: _corrections(json['corrections']),
    );

/// Decodes a completed Summarizer result.
TextSummarizerResult decodeTextSummarizerResult(Map<String, dynamic> json) =>
    TextSummarizerResult(summary: json['summary'] as String?);

/// Decodes one streamed Summarizer update.
TextSummarizerUpdate decodeTextSummarizerUpdate(Map<String, dynamic> json) =>
    TextSummarizerUpdate(
      chunk: json['chunk'] as String?,
      done: json['done'] == true,
    );

/// Google's correction types, named as its Java and C enums (`SAME`,
/// `INSERTION`, `DELETION`), in its order.
List<ProofreadingCorrection> _corrections(Object? value) => [
  for (final correction in (value as List? ?? const []).cast<Map>())
    ProofreadingCorrection(
      type: ProofreadingCorrectionType.values.byName(
        (correction['type'] as String).toLowerCase(),
      ),
      text: correction['text'] as String? ?? '',
    ),
];

List<Classifications> _classifications(Map<String, dynamic> json) => [
  for (final head in (json['classifications'] as List).cast<Map>())
    decodeClassifications(head),
];

int? _timestamp(Map<String, dynamic> json) =>
    (json['timestampMs'] as num?)?.toInt();
