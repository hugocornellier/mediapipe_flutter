// Needs Flutter's test binding; `dart test` skips it (tag `flutter`).
@Tags(['flutter'])
library;

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_text/mediapipe_text.dart';
import 'package:mediapipe_text/mediapipe_text_android.dart';

/// The Android plugin's replies, shaped as its Java side sends them, run
/// through the Dart adapter and the shared decoder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('mediapipe_text/android');
  late List<MethodCall> calls;
  late Object? Function(MethodCall) reply;
  final model = Uint8List.fromList([1]);

  setUp(() {
    calls = [];
    MediaPipeTextAndroid.registerWith();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'create' => 3,
        'run' => reply(call),
        _ => null,
      };
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('classifier settings travel in Google JavaScript names', () async {
    reply = (_) => {
      'timestampMs': 0,
      'classifications': [
        {
          'headIndex': 0,
          'headName': '',
          'categories': [
            {
              'index': 1,
              'score': 0.75,
              'categoryName': 'positive',
              'displayName': '',
            },
          ],
        },
      ],
    };
    final task = await TextClassifier.create(
      TextClassifierOptions(modelBytes: model, categoryDenylist: ['negative']),
    );
    final result = await task.classify('Hello');
    final created = calls.first.arguments as Map;
    expect(created['task'], 'text_classifier');
    expect(created['scoreThreshold'], 0.0);
    expect(created.containsKey('maxResults'), isFalse);
    expect(created['categoryDenylist'], ['negative']);
    expect(calls[1].arguments, {'id': 3, 'text': 'Hello'});
    final head = result.classifications.single;
    expect(head.headName, isNull);
    expect(head.categories.single.displayName, isNull);
    expect(result.timestampMilliseconds, 0);
    await task.dispose();
    expect(calls.last.method, 'close');
  });

  test('Java float and int arrays decode as embeddings', () async {
    reply = (_) => {
      'embeddings': [
        {
          'floatEmbedding': Float32List.fromList([0.5, -0.5]),
          'headIndex': 0,
          'headName': 'head',
        },
        {
          'quantizedEmbedding': Int32List.fromList([1, 255]),
          'headIndex': 1,
          'headName': '',
        },
      ],
    };
    final task = await TextEmbedder.create(
      TextEmbedderOptions(modelBytes: model, quantize: true),
    );
    final [floats, bytes] = (await task.embed('Hello')).embeddings;
    expect(floats.floatEmbedding, [0.5, -0.5]);
    expect(bytes.quantizedEmbedding, [1, 255]);
    await expectLater(
      task.embed(
        'Hello',
        formatContext: TextFormatContext(
          taskType: EmbeddingType.semanticSimilarity,
        ),
      ),
      throwsA(isA<RuntimeUnavailableException>()),
    );
    await task.dispose();
  });

  test(
    'plugin errors become TaskException; requests after dispose fail',
    () async {
      reply = (_) => throw PlatformException(code: 'run', message: 'Bad text.');
      final task = await LanguageDetector.create(
        LanguageDetectorOptions(modelBytes: model),
      );
      await expectLater(
        task.detect('Hello'),
        throwsA(
          isA<TaskException>().having((e) => e.message, 'message', 'Bad text.'),
        ),
      );
      await expectLater(task.detect('bad\u0000text'), throwsArgumentError);
      await task.dispose();
      await expectLater(task.detect('Hello'), throwsStateError);
    },
  );

  test('the GPU delegate is refused before the plugin is called', () async {
    await expectLater(
      TextClassifier.create(
        TextClassifierOptions(modelBytes: model, delegate: Delegate.gpu),
      ),
      throwsA(isA<RuntimeUnavailableException>()),
    );
    expect(calls, isEmpty);
  });
}
