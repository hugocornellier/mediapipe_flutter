@Tags(['native-assets'])
library;

import 'package:mediapipe_flutter_text/mediapipe_flutter_text.dart';
import 'package:test/test.dart';

void main() {
  test(
    'public classifier returns the reference scores through its isolate',
    () async {
      final classifier = TextClassifier(
        TextClassifierOptions.fromAssetPath(
          'example/assets/bert_classifier.tflite',
        ),
      );
      final result = await classifier.classify('Hello, world!');
      addTearDown(classifier.dispose);
      addTearDown(result.dispose);
      final positive = result.classifications.first.categories.first;
      expect(positive.categoryName, 'positive');
      expect(positive.score, closeTo(0.9919, 0.0009));
    },
  );

  test(
    'public detector handles consecutive languages through its isolate',
    () async {
      final detector = LanguageDetector(
        LanguageDetectorOptions.fromAssetPath(
          'example/assets/language_detector.tflite',
        ),
      );
      final english = await detector.detect('Hello, world!');
      addTearDown(detector.dispose);
      addTearDown(english.dispose);
      final spanish = await detector.detect('Quiero agua, por favor.');
      addTearDown(spanish.dispose);
      expect(english.predictions.first.languageCode, 'en');
      expect(spanish.predictions.first.languageCode, 'es');
      expect(spanish.predictions.first.probability, greaterThan(0.99));
    },
  );

  test('public embedder supports embedding and native similarity', () async {
    final embedder = TextEmbedder(
      TextEmbedderOptions.fromAssetPath(
        'example/assets/universal_sentence_encoder.tflite',
      ),
    );
    final first = await embedder.embed('Hello, world!');
    addTearDown(embedder.dispose);
    addTearDown(first.dispose);
    final second = await embedder.embed('Hello, world!');
    addTearDown(second.dispose);
    expect(first.embeddings.first.floatEmbedding, hasLength(100));
    expect(
      await embedder.cosineSimilarity(
        first.embeddings.first,
        second.embeddings.first,
      ),
      closeTo(1, 0.0001),
    );
  });
}
