import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_audio/audio_task_backend.dart';
import 'package:mediapipe_flutter_audio/mediapipe_flutter_audio.dart';
import 'package:mediapipe_flutter_core/mediapipe_flutter_core.dart'
    show ClassifierOptions, EmbedderOptions;
import 'package:mediapipe_flutter_text/mediapipe_flutter_text.dart';
import 'package:mediapipe_flutter_text/text_task_backend.dart';

/// Text Classifier, Text Embedder, Language Detector and Audio Classifier
/// through Google's official mobile SDKs (the text and audio packages' Android
/// plugins; on iOS the vision package's SDK adapter, which core's runtime
/// resolves to), against Google's own 1.0.1 outputs for the same inputs (the
/// packages' checked-in references, from the macOS wheel).
/// Another runtime build on another CPU, so scores get a cross-runtime bound.
/// Runs on the Android emulator and iOS simulator in CI, and on phones.
const _scoreBound = 2e-3;

/// YAMNet reports scores in 1/256 steps; allow two steps.
const _audioBound = 2 / 256;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List> asset(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  testWidgets('official SDK text tasks match Google\'s references', (
    tester,
  ) async {
    await tester.runAsync(() async {
      expect(Platform.isAndroid || Platform.isIOS, isTrue);
      // Android's plugin registers a backend; iOS runs the native bindings.
      expect(
        textTaskBackendFactory != null,
        Platform.isAndroid,
        reason: 'the text SDK plugin must register automatically on Android',
      );
      final bert = await asset('assets/models/bert_classifier.tflite');
      for (final (text, options, expected)
          in <(String, ClassifierOptions, List<(String, double)>)>[
            (
              'Hello, world!',
              const ClassifierOptions(),
              [('positive', 0.992178), ('negative', 0.007822)],
            ),
            (
              'This was a terrible movie. I hated every minute.',
              const ClassifierOptions(),
              [('negative', 0.998278), ('positive', 0.001722)],
            ),
            (
              'Hello, world!',
              const ClassifierOptions(maxResults: 1),
              [('positive', 0.992178)],
            ),
            (
              'Hello, world!',
              const ClassifierOptions(categoryDenylist: ['positive']),
              [('negative', 0.007822)],
            ),
            ('Hello, world!', const ClassifierOptions(scoreThreshold: 1), []),
          ]) {
        final task = await TextClassifier.create(
          TextClassifierOptions.fromAssetBuffer(
            bert,
            classifierOptions: options,
          ),
        );
        try {
          final result = await task.classify(text);
          final categories = result.classifications.single.categories.toList();
          expect(categories.map((c) => c.categoryName), [
            for (final e in expected) e.$1,
          ]);
          for (final (i, (_, score)) in expected.indexed) {
            expect(categories[i].score, closeTo(score, _scoreBound));
          }
          expect(result.classifications.single.headName, 'probability');
        } finally {
          await task.dispose();
        }
      }
      // Requests run in order; none is accepted after disposal.
      final ordered = await TextClassifier.create(
        TextClassifierOptions.fromAssetBuffer(bert),
      );
      final results = await Future.wait([
        ordered.classify('Hello, world!'),
        ordered.classify('This was a terrible movie. I hated every minute.'),
      ]);
      expect(
        results.map(
          (r) => r.classifications.single.categories.first.categoryName,
        ),
        ['positive', 'negative'],
      );
      await ordered.dispose();
      await ordered.dispose();
      expect(() => ordered.classify('Hello'), throwsStateError);
      await expectLater(
        TextClassifier.create(
          TextClassifierOptions.fromAssetBuffer(Uint8List.fromList([1, 2, 3])),
        ),
        throwsA(isA<TextTaskException>()),
      );

      final use = await asset(
        'assets/models/universal_sentence_encoder.tflite',
      );
      final embedder = await TextEmbedder.create(
        TextEmbedderOptions.fromAssetBuffer(use),
      );
      try {
        final greeting = (await embedder.embed(
          'Hello, world!',
        )).embeddings.single;
        final related = (await embedder.embed(
          'Hello there!',
        )).embeddings.single;
        final different = (await embedder.embed(
          'The spacecraft landed on Mars.',
        )).embeddings.single;
        expect(greeting.length, 100);
        expect(greeting.headIndex, 1);
        expect(greeting.headName, 'response_encoding');
        const first = [
          1.7475107908248901,
          -0.12642768025398254,
          -0.21085068583488464,
          1.524668574333191,
        ];
        for (final (i, value) in first.indexed) {
          expect(greeting.floatEmbedding![i], closeTo(value, _scoreBound));
        }
        expect(
          await embedder.cosineSimilarity(greeting, related),
          closeTo(0.9605238, _scoreBound),
        );
        expect(
          await embedder.cosineSimilarity(greeting, different),
          closeTo(0.8081205, _scoreBound),
        );
      } finally {
        await embedder.dispose();
      }
      final quantizer = await TextEmbedder.create(
        TextEmbedderOptions.fromAssetBuffer(
          use,
          embedderOptions: const EmbedderOptions(
            l2Normalize: true,
            quantize: true,
          ),
        ),
      );
      try {
        final a = (await quantizer.embed('Hello, world!')).embeddings.single;
        final b = (await quantizer.embed('Hello there!')).embeddings.single;
        expect(a.isQuantized, isTrue);
        expect(a.quantizedEmbedding, hasLength(100));
        expect(
          await quantizer.cosineSimilarity(a, b),
          closeTo(0.9590452, 1e-2),
        );
      } finally {
        await quantizer.dispose();
      }

      final detector = await LanguageDetector.create(
        LanguageDetectorOptions.fromAssetBuffer(
          await asset('assets/models/language_detector.tflite'),
          classifierOptions: const ClassifierOptions(maxResults: 3),
        ),
      );
      try {
        for (final (text, expected) in [
          (
            'Hello, world!',
            [('en', 0.994802), ('de', 0.001138), ('hu', 0.000523)],
          ),
          (
            'Quiero agua, por favor.',
            [('es', 0.998336), ('gl', 0.001423), ('pt', 0.000164)],
          ),
          (
            'こんにちは、元気ですか？',
            [('ja', 0.99923), ('ms', 0.000075), ('id', 0.000041)],
          ),
        ]) {
          final predictions = (await detector.detect(
            text,
          )).predictions.toList();
          expect(predictions.first.languageCode, expected.first.$1);
          for (final (i, (_, probability)) in expected.indexed) {
            expect(
              predictions[i].probability,
              closeTo(probability, _scoreBound),
            );
          }
        }
      } finally {
        await detector.dispose();
      }
      _report('text', {'checks': 'classifier, embedder, language detector'});
    });
  }, skip: !(Platform.isAndroid || Platform.isIOS));

  testWidgets('official SDK Audio Classifier matches Google\'s reference', (
    tester,
  ) async {
    await tester.runAsync(() async {
      expect(
        audioTaskBackendFactory != null,
        Platform.isAndroid,
        reason: 'the audio SDK plugin must register automatically on Android',
      );
      final task = await AudioClassifier.create(
        AudioClassifierOptions(
          modelBytes: await asset('assets/models/yamnet.tflite'),
          maxResults: 3,
        ),
      );
      try {
        final chunks = await task.classify(
          decodeWav(await asset('assets/samples/speech_16000_hz_mono.wav')),
        );
        const expected = [
          (0, 'Speech', 0.917969),
          (975, 'Speech', 0.992188),
          (1950, 'Speech', 0.984375),
          (2925, 'Speech', 0.996094),
          (3900, 'Tick', 0.261719),
        ];
        expect(chunks, hasLength(expected.length));
        var worst = 0.0;
        for (final (i, (timestamp, name, score)) in expected.indexed) {
          expect(chunks[i].timestampMs, timestamp);
          expect(chunks[i].categories.first.name, name);
          expect(chunks[i].categories.first.score, closeTo(score, _audioBound));
          worst = math.max(
            worst,
            (chunks[i].categories.first.score - score).abs(),
          );
        }
        // The 48 kHz recording of the same speech is resampled by Google's
        // task; it must still hear speech first.
        final resampled = await task.classify(
          decodeWav(await asset('assets/samples/speech_48000_hz_mono.wav')),
        );
        expect(resampled.first.categories.first.name, 'Speech');
        _report('audio', {'max_top_score_delta': worst});
      } finally {
        await task.dispose();
      }
      expect(
        () => task.classify(
          AudioData(samples: Float32List(16000), sampleRate: 16000),
        ),
        throwsStateError,
      );
      // The default options: every category, as the native API returns.
      final every = await AudioClassifier.create(
        AudioClassifierOptions(
          modelBytes: await asset('assets/models/yamnet.tflite'),
        ),
      );
      try {
        final chunks = await every.classify(
          decodeWav(await asset('assets/samples/speech_16000_hz_mono.wav')),
        );
        expect(chunks.first.categories.first.name, 'Speech');
        expect(chunks.first.categories, hasLength(greaterThan(3)));
      } finally {
        await every.dispose();
      }
      await expectLater(
        AudioClassifier.create(
          AudioClassifierOptions(modelBytes: Uint8List.fromList([1, 2, 3])),
        ),
        throwsA(isA<AudioClassifierException>()),
      );
    });
  }, skip: !(Platform.isAndroid || Platform.isIOS));
}

// Kept in the device log (logcat, the simulator console) for the record.
void _report(String event, Map<String, Object?> data) {
  // ignore: avoid_print
  print('SDK_TEXT_AUDIO ${jsonEncode({'event': event, ...data})}');
}
