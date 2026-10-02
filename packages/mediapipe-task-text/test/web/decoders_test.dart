@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_text/mediapipe_text.dart';
import 'package:mediapipe_text/src/results/decoders.dart';

/// The browser worker's replies, as JSON text, through the shared decoder.
Map<String, dynamic> _json(String text) =>
    jsonDecode(text) as Map<String, dynamic>;

void main() {
  test('classification heads, absent labels and the request stamp', () {
    final result = decodeTextClassifierResult(
      _json('''{"timestampMs": 1000, "classifications": [{"headIndex": 0,
        "headName": "probability", "categories": [{"index": 1, "score": 0.99,
        "categoryName": "positive", "displayName": ""}]}]}'''),
    );
    final category = result.classifications.single.categories.single;
    expect(result.timestampMilliseconds, 1000);
    expect(result.classifications.single.headName, 'probability');
    expect(category.categoryName, 'positive');
    expect(category.displayName, isNull);
    expect(() => result.classifications.clear(), throwsUnsupportedError);
  });

  test('float and quantized embeddings', () {
    final result = decodeTextEmbedderResult(
      _json('''{"embeddings": [{"headIndex": 0, "headName": "",
        "floatEmbedding": [0.5, -0.25]}, {"headIndex": 1,
        "headName": "quantized", "quantizedEmbedding": [1, 255]}]}'''),
    );
    final [floats, bytes] = result.embeddings;
    expect(result.timestampMilliseconds, isNull);
    expect(floats.floatEmbedding, [0.5, -0.25]);
    expect(floats.headName, isNull);
    expect(bytes.quantizedEmbedding, [1, 255]);
    expect(TextEmbedder.cosineSimilarity(bytes, bytes), closeTo(1, 1e-12));
  });

  test('language predictions keep their order', () {
    final result = decodeLanguageDetectorResult(
      _json('''{"languages": [{"languageCode": "es", "probability": 0.9},
        {"languageCode": "en", "probability": 0.1}]}'''),
    );
    expect(result.predictions, const [
      LanguagePrediction(languageCode: 'es', probability: 0.9),
      LanguagePrediction(languageCode: 'en', probability: 0.1),
    ]);
  });

  test('proofreader and summarizer results and updates', () {
    final result = decodeTextProofreaderResult(
      _json('''{"proofreadText": "She goes home.", "corrections": [
        {"type": "SAME", "text": "She "}, {"type": "DELETION", "text": "go"},
        {"type": "INSERTION", "text": "goes"}]}'''),
    );
    expect(result.proofreadText, 'She goes home.');
    expect(result.corrections.map((c) => c.type), [
      ProofreadingCorrectionType.same,
      ProofreadingCorrectionType.deletion,
      ProofreadingCorrectionType.insertion,
    ]);
    expect(() => result.corrections.clear(), throwsUnsupportedError);
    final update = decodeTextProofreaderUpdate(
      _json('{"chunk": null, "corrections": null, "done": true}'),
    );
    expect(update.chunk, isNull);
    expect(update.done, isTrue);
    expect(update.corrections, isEmpty);
    expect(
      decodeTextSummarizerResult(_json('{"summary": "- A point"}')).summary,
      '- A point',
    );
    final chunk = decodeTextSummarizerUpdate(
      _json('{"chunk": "- A", "done": false}'),
    );
    expect(chunk.chunk, '- A');
    expect(chunk.done, isFalse);
  });

  test('generative tasks report their platforms before loading', () async {
    final support = await queryTextSummarizerCapabilities();
    expect(support.isSupported, isFalse);
    await expectLater(
      TextSummarizer.create(TextSummarizerOptions(modelPath: 'model')),
      throwsA(isA<RuntimeUnavailableException>()),
    );
  });
}
