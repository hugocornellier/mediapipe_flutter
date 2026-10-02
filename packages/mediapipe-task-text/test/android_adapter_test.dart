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

  test(
    'the update handler is installed with the first task, not at registration',
    () async {
      // Flutter registers plugins before its binding exists, so a handler set
      // in registerWith would have no messenger, and streams would wait
      // forever for updates that reach nothing.
      Future<ByteData?> deliver() async {
        ByteData? answer;
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            const MethodCall('update', {'request': 0, 'result': {}}),
          ),
          (data) => answer = data,
        );
        return answer;
      }

      // The first test in this file: no task has been created yet.
      MediaPipeTextAndroid.registerWith();
      // No handler yet: the message gets no reply.
      expect(await deliver(), isNull);
      await TextSummarizer.create(
        TextSummarizerOptions(modelPath: '/models/summarizer'),
      );
      expect(await deliver(), isNotNull);
    },
  );

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
    expect(calls.last.arguments, {'id': 3, 'text': 'Hello'});
    // EmbeddingGemma's format context travels in Google's JavaScript names,
    // which the plugin maps onto its Java TextFormatContext.
    await task.embed(
      'Hello',
      formatContext: TextFormatContext(
        taskType: EmbeddingType.retrievalDocument,
        title: 'Greetings',
        role: TextRole.document,
      ),
    );
    expect(calls.last.arguments, {
      'id': 3,
      'text': 'Hello',
      'formatContext': {
        'type': 'RETRIEVAL_DOCUMENT',
        'title': 'Greetings',
        'textRole': 'DOCUMENT',
      },
    });
    await task.embed(
      'Hello',
      formatContext: TextFormatContext(taskType: EmbeddingType.clustering),
    );
    expect((calls.last.arguments as Map)['formatContext'], {
      'type': 'CLUSTERING',
      'textRole': 'QUERY',
    });
    await task.dispose();
  });

  /// Sends one of the plugin's streamed updates to the Dart adapter.
  Future<void> update(Map<String, Object?> event) async {
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('update', event)),
      (_) {},
    );
  }

  test('generative options travel in Google Java names; results and '
      'streamed updates decode', () async {
    reply = (_) => {
      'proofreadText': 'She goes home.',
      'corrections': [
        {'type': 'SAME', 'text': 'She '},
        {'type': 'DELETION', 'text': 'go'},
        {'type': 'INSERTION', 'text': 'goes'},
        {'type': 'SAME', 'text': ' home.'},
      ],
    };
    final task = await TextProofreader.create(
      TextProofreaderOptions(
        modelPath: '/models/proofreader',
        maxNumTokens: 64,
      ),
    );
    expect(calls.first.arguments, {
      'task': 'text_proofreader',
      'modelPath': '/models/proofreader',
      'maxNumTokens': 64,
    });
    final result = await task.proofread('She go home.');
    expect(result.proofreadText, 'She goes home.');
    expect(result.corrections.map((c) => c.type.name), [
      'same',
      'deletion',
      'insertion',
      'same',
    ]);
    expect(result.corrections[1].text, 'go');

    final updates = task.proofreadStream('She go home.').toList();
    // Updates arrive once the plugin has accepted the stream request.
    await Future<void>.delayed(Duration.zero);
    final stream = calls.last;
    expect(stream.method, 'stream');
    expect((stream.arguments as Map)['text'], 'She go home.');
    final request = (stream.arguments as Map)['request'];
    await update({
      'request': request,
      'result': {'chunk': 'She ', 'corrections': [], 'done': false},
    });
    await update({
      'request': 999,
      'result': {'chunk': 'x', 'done': true},
    });
    await update({
      'request': request,
      'result': {
        'chunk': 'goes home.',
        'corrections': [
          {'type': 'SAME', 'text': 'She goes home.'},
        ],
        'done': true,
      },
    });
    final received = await updates;
    expect(received.map((u) => u.chunk), ['She ', 'goes home.']);
    expect(received.map((u) => u.done), [false, true]);
    expect(received.last.corrections.single.text, 'She goes home.');
    await task.dispose();
    expect(calls.last.method, 'close');
  });

  test("a summarizer's mode travels as Google's Java Mode name; stream "
      'errors are TaskException', () async {
    final task = await TextSummarizer.create(
      TextSummarizerOptions(
        modelPath: '/models/summarizer',
        mode: TextSummarizerMode.tldr,
      ),
    );
    expect(calls.first.arguments, {
      'task': 'text_summarizer',
      'modelPath': '/models/summarizer',
      'mode': 'TLDR',
    });
    final updates = task.summarizeStream('A long text.').toList();
    await Future<void>.delayed(Duration.zero);
    final request = (calls.last.arguments as Map)['request'];
    await update({'request': request, 'error': 'Input too long.'});
    await expectLater(
      updates,
      throwsA(
        isA<TaskException>().having(
          (e) => e.message,
          'message',
          'Input too long.',
        ),
      ),
    );
    await task.dispose();
  });

  test(
    'a cache directory is refused on Android before the plugin runs',
    () async {
      await expectLater(
        TextSummarizer.create(
          TextSummarizerOptions(
            modelPath: '/models/summarizer',
            cacheDirectory: '/cache',
          ),
        ),
        throwsA(
          isA<RuntimeUnavailableException>().having(
            (e) => e.fix,
            'fix',
            contains('cacheDirectory'),
          ),
        ),
      );
      expect(calls, isEmpty);
    },
  );

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
