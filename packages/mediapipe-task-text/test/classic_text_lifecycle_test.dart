@Tags(['native-assets'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediapipe_flutter_core/io.dart';
import 'package:mediapipe_flutter_text/io.dart';
import 'package:test/test.dart';

typedef _Task = (Future<Object> Function(String), Future<void> Function());

_Task _start(String name, BaseOptions model) {
  switch (name) {
    case 'classifier':
      final task = TextClassifier(TextClassifierOptions(baseOptions: model));
      return (task.classify, task.dispose);
    case 'embedder':
      final task = TextEmbedder(TextEmbedderOptions(baseOptions: model));
      return (task.embed, task.dispose);
    default:
      final task = LanguageDetector(
        LanguageDetectorOptions(baseOptions: model),
      );
      return (task.detect, task.dispose);
  }
}

Object _values(Object result) => switch (result) {
  TextClassifierResult r => [
    for (final h in r.classifications)
      [
        for (final c in h.categories) [c.categoryName, c.index, c.score],
      ],
  ],
  TextEmbedderResult r => [
    for (final e in r.embeddings) e.floatEmbedding!.toList(),
  ],
  LanguageDetectorResult r => [
    for (final p in r.predictions) [p.languageCode, p.probability],
  ],
  _ => throw StateError('Unexpected result'),
};

void main() {
  const models = {
    'classifier': 'example/assets/bert_classifier.tflite',
    'embedder': 'example/assets/universal_sentence_encoder.tflite',
    'language': 'example/assets/language_detector.tflite',
  };
  for (final entry in models.entries) {
    final name = entry.key;
    final model = BaseOptions.path(entry.value);
    group(name, () {
      test(
        'preserves concurrent response order and drains disposal during startup',
        () async {
          const inputs = [
            'Hello, world!',
            'This is terrible.',
            'Quiero agua, por favor.',
            '',
            'こんにちは',
          ];
          final (reference, closeReference) = _start(name, model);
          final expected = <Object>[];
          try {
            for (final text in inputs) {
              expected.add(_values(await reference(text)));
            }
          } finally {
            await closeReference();
          }
          final (run, close) = _start(name, model);
          final pending = [for (final text in inputs) run(text)];
          final closing = close();
          expect(identical(closing, close()), isTrue);
          await expectLater(run('Too late'), throwsStateError);
          final results = await Future.wait(pending);
          await closing;
          expect(results.map(_values).toList(), expected);
          await close();
        },
      );

      test(
        'can dispose before any inference and recreate repeatedly',
        () async {
          for (var i = 0; i < 3; i++) {
            final (run, close) = _start(name, model);
            await close().timeout(const Duration(seconds: 10));
            await expectLater(run('Late'), throwsStateError);
          }
        },
      );

      test(
        'initialization errors reach pending calls and disposal without hangs',
        () async {
          for (final bad in [
            BaseOptions.path('/nonexistent/mediapipe-model.tflite'),
            BaseOptions.memory(Uint8List.fromList([1, 2, 3, 4])),
          ]) {
            final (run, close) = _start(name, bad);
            // Let initialization fail before attaching an inference listener.
            await Future<void>.delayed(const Duration(milliseconds: 50));
            final failure = throwsA(
              isA<TextTaskException>().having(
                (e) => e.message,
                'message',
                isNotEmpty,
              ),
            );
            await expectLater(
              run('Hello').timeout(const Duration(seconds: 10)),
              failure,
            );
            await expectLater(
              close().timeout(const Duration(seconds: 10)),
              failure,
            );
            await expectLater(run('Late'), throwsStateError);
          }
          final (run, close) = _start(name, model);
          try {
            expect(await run('Hello'), isNotNull);
          } finally {
            await close();
          }
        },
      );

      test('rejects NUL without poisoning a valid task', () async {
        final (run, close) = _start(name, model);
        try {
          await expectLater(run('Hello\u0000ignored'), throwsArgumentError);
          expect(await run('Hello'), isNotNull);
        } finally {
          await close();
        }
      });
    });
  }

  test(
    'options snapshot model bytes and filter lists and are reusable',
    () async {
      final bytes = File(models['classifier']!).readAsBytesSync();
      final allow = ['positive'];
      final options = TextClassifierOptions.fromAssetBuffer(
        bytes,
        classifierOptions: ClassifierOptions(categoryAllowlist: allow),
      );
      bytes.fillRange(0, bytes.length, 0);
      allow[0] = 'negative';
      expect(
        () => options.baseOptions.modelAssetBuffer![0] = 0,
        throwsUnsupportedError,
      );
      expect(
        () => options.classifierOptions.categoryAllowlist!.clear(),
        throwsUnsupportedError,
      );
      for (var i = 0; i < 2; i++) {
        final task = await TextClassifier.create(options);
        try {
          expect(
            (await task.classify(
              'Hello, world!',
            )).classifications.single.categories.single.categoryName,
            'positive',
          );
        } finally {
          await task.dispose();
        }
      }
    },
  );

  test('async factories report invalid models immediately', () async {
    await expectLater(
      TextClassifier.create(
        TextClassifierOptions.fromAssetPath('/nonexistent/model'),
      ),
      throwsA(isA<TextTaskException>()),
    );
    await expectLater(
      TextEmbedder.create(
        TextEmbedderOptions.fromAssetPath('/nonexistent/model'),
      ),
      throwsA(isA<TextTaskException>()),
    );
    await expectLater(
      LanguageDetector.create(
        LanguageDetectorOptions.fromAssetPath('/nonexistent/model'),
      ),
      throwsA(isA<TextTaskException>()),
    );
  });

  test('rejects truncated C strings and unrepresentable option values', () {
    expect(
      () => TextClassifierOptions.fromAssetPath('model\u0000suffix'),
      throwsArgumentError,
    );
    expect(
      () => TextEmbedderOptions.fromAssetBuffer(Uint8List(0)),
      throwsArgumentError,
    );
    expect(
      () => LanguageDetectorOptions.fromAssetPath(
        'model',
        classifierOptions: ClassifierOptions(categoryAllowlist: ['en\u0000fr']),
      ),
      throwsArgumentError,
    );
    expect(
      () => TextClassifierOptions.fromAssetPath(
        'model',
        classifierOptions: ClassifierOptions(maxResults: 0x80000000),
      ),
      throwsArgumentError,
    );
    expect(
      () => TextClassifierOptions.fromAssetPath(
        'model',
        classifierOptions: ClassifierOptions(scoreThreshold: double.nan),
      ),
      throwsArgumentError,
    );
  });

  test(
    'similarity works with owned vectors and rejects invalid comparisons',
    () async {
      final task = await TextEmbedder.create(
        TextEmbedderOptions.fromAssetPath(models['embedder']!),
      );
      try {
        final a = Embedding.quantized(
          Uint8List.fromList([127, 128]),
          headIndex: 0,
        );
        final b = Embedding.quantized(
          Uint8List.fromList([128, 127]),
          headIndex: 0,
        );
        expect(await task.cosineSimilarity(a, b), lessThan(-.99));
        await expectLater(
          task.cosineSimilarity(
            a,
            Embedding.float(Float32List.fromList([1, 2]), headIndex: 0),
          ),
          throwsArgumentError,
        );
        await expectLater(
          task.cosineSimilarity(
            a,
            Embedding.quantized(Uint8List(2), headIndex: 0),
          ),
          throwsArgumentError,
        );
      } finally {
        await task.dispose();
      }
    },
  );
}
