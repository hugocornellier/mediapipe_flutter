import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_core/mediapipe_flutter_core.dart'
    show ClassifierOptions, EmbedderOptions;
import 'package:mediapipe_flutter_text/mediapipe_flutter_text.dart';

// The text demos' three tasks, from the gallery's bundled models, in the same
// app as the vision runtimes: core's shared runtime must load and answer beside
// them on macOS arm64, Linux x64 and Windows x64, where prepare.py bundles
// them. The mobile and browser plugins have sdk_text_audio_test.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List> model(String name) async {
    final data = await rootBundle.load('assets/models/$name');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  testWidgets('text classifier, language detector and embedder answer', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final classifier = await TextClassifier.create(
        TextClassifierOptions.fromAssetBuffer(
          await model('bert_classifier.tflite'),
          classifierOptions: const ClassifierOptions(maxResults: 2),
        ),
      );
      try {
        final result = await classifier.classify(
          'I loved this movie, it was wonderful!',
        );
        final top = result.classifications.first.categories.first;
        expect(top.categoryName, 'positive');
        expect(top.score, greaterThan(0.9));
      } finally {
        await classifier.dispose();
      }

      final detector = await LanguageDetector.create(
        LanguageDetectorOptions.fromAssetBuffer(
          await model('language_detector.tflite'),
        ),
      );
      try {
        final result = await detector.detect('Merci beaucoup pour votre aide.');
        expect(result.predictions.first.languageCode, 'fr');
      } finally {
        await detector.dispose();
      }

      final embedder = await TextEmbedder.create(
        TextEmbedderOptions.fromAssetBuffer(
          await model('universal_sentence_encoder.tflite'),
          embedderOptions: const EmbedderOptions(l2Normalize: true),
        ),
      );
      try {
        final a = await embedder.embed('The weather is lovely today.');
        final b = await embedder.embed("It's a beautiful sunny day.");
        final c = await embedder.embed('The invoice is overdue.');
        final close = await embedder.cosineSimilarity(
          a.embeddings.first,
          b.embeddings.first,
        );
        final far = await embedder.cosineSimilarity(
          a.embeddings.first,
          c.embeddings.first,
        );
        expect(close, greaterThan(far));
      } finally {
        await embedder.dispose();
      }
    });
  }, skip: !(Platform.isMacOS || Platform.isLinux || Platform.isWindows));
}
