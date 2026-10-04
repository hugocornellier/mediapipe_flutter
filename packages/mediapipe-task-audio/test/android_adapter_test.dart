// Needs Flutter's test binding; `dart test` skips it (tag `flutter`).
@Tags(['flutter'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_audio/mediapipe_audio.dart';
import 'package:mediapipe_audio/mediapipe_audio_android.dart';

import 'support/audio_model.dart';

/// The Android plugin's replies, shaped as its Java side sends them, run
/// through the Dart adapter and the shared decoder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('mediapipe_audio/android');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    MediaPipeAudioAndroid.registerWith();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'create' => 5,
        'run' => [
          {
            'timestampMs': 0,
            'classifications': [
              {
                'headIndex': 0,
                'headName': '',
                'categories': [
                  {
                    'index': 0,
                    'score': 0.8,
                    'categoryName': 'Speech',
                    'displayName': '',
                  },
                ],
              },
            ],
          },
        ],
        _ => null,
      };
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('settings, a stereo clip averaged to mono, and the result', () async {
    final task = await AudioClassifier.create(
      AudioClassifierOptions(
        modelBytes: Uint8List.fromList([1]),
        maxResults: 2,
        categoryDenylist: ['Music'],
      ),
    );
    final [chunk] = await task.classify(
      AudioData(
        samples: Float32List.fromList([1, 0, 0.5, 0.5]),
        sampleRate: 16000,
        channels: 2,
      ),
    );
    final created = calls.first.arguments as Map;
    expect(created['maxResults'], 2);
    expect(created['scoreThreshold'], 0.0);
    expect(created['categoryDenylist'], ['Music']);
    expect(created.containsKey('categoryAllowlist'), isFalse);
    expect((calls[1].arguments as Map)['samples'], [0.5, 0.5]);
    final category = chunk.classifications.single.categories.single;
    expect(category.categoryName, 'Speech');
    expect(category.displayName, isNull);
    await task.dispose();
    expect(calls.last.method, 'close');
  });

  /// One window's result as the plugin's listener sends it, under [request].
  Map<String, Object?> update(int request, int timestamp, String name) => {
    'request': request,
    'result': {
      'timestampMs': timestamp,
      'classifications': [
        {
          'headIndex': 0,
          'headName': '',
          'categories': [
            {'index': 0, 'score': 0.5, 'categoryName': name, 'displayName': ''},
          ],
        },
      ],
    },
  };

  /// What the plugin's TaskHost.emit does: an `update` call to Dart.
  Future<void> post(Map<String, Object?> event) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall('update', event)),
      (_) {},
    );
  }

  final model = audioModel(window: 15600, rate: 16000, channels: 1);

  test('a stream: its blocks, its updates by request, and its close', () async {
    late int request;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'create':
          request = (call.arguments as Map)['request'] as int;
          return 9;
        case 'close':
          // Google's close flushes the tail; the plugin posts its update to
          // the platform thread before the reply to the close.
          await post(update(request, 9223372036854775, 'tail'));
          return null;
      }
      return null;
    });
    final task = await AudioClassifier.create(
      AudioClassifierOptions(
        modelBytes: model,
        maxResults: 3,
        runningMode: AudioRunningMode.audioStream,
      ),
    );
    final created = calls.single.arguments as Map;
    expect(created['runningMode'], 'AUDIO_STREAM');
    expect(created['maxResults'], 3);
    expect(created['modelBytes'], model);
    final heard = <AudioClassifierResult>[];
    final done = Completer<void>();
    task.results.listen(heard.add, onDone: done.complete);
    final stereo = Float32List.fromList([
      for (var i = 0; i < 3200; i++) i / 3200,
    ]);
    task
      ..classifyAsync(
        AudioData(samples: stereo, sampleRate: 16000, channels: 2),
        timestampMilliseconds: 3000000000,
      )
      ..classifyAsync(
        AudioData(samples: Float32List(16000), sampleRate: 16000),
        timestampMilliseconds: 3000000100,
      );
    await Future<void>.delayed(Duration.zero);
    final sends = [
      for (final call in calls)
        if (call.method == 'send') call,
    ];
    expect(sends, hasLength(2));
    final first = sends.first.arguments as Map;
    expect(first['id'], 9);
    expect(first['channels'], 2);
    expect(first['sampleRate'], 16000.0);
    // 64 bits: past 2^31, as a wall clock in milliseconds is.
    expect(first['timestampMs'], 3000000000);
    expect(first['samples'], stereo);
    // Another request's update is not this stream's.
    await post(update(request + 1, 1, 'elsewhere'));
    await post(update(request, 3000000000, 'first'));
    await task.dispose();
    await done.future;
    expect(calls.last.method, 'close');
    expect(
      [
        for (final r in heard)
          (
            r.timestampMilliseconds,
            r.classifications.single.categories.single.categoryName,
          ),
      ],
      [(3000000000, 'first'), (3000000975, 'tail')],
    );
  });

  test('an error update ends the stream with Google\'s message', () async {
    late int request;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'create') {
        request = (call.arguments as Map)['request'] as int;
        return 4;
      }
      return null;
    });
    final task = await AudioClassifier.create(
      AudioClassifierOptions(
        modelBytes: model,
        runningMode: AudioRunningMode.audioStream,
      ),
    );
    final errors = <Object>[];
    final done = Completer<void>();
    task.results.listen((_) {}, onError: errors.add, onDone: done.complete);
    task.classifyAsync(
      AudioData(samples: Float32List(1600), sampleRate: 16000),
      timestampMilliseconds: 0,
    );
    await post({
      'request': request,
      'error': 'Mediapipe error: Graph has errors.',
    });
    await done.future;
    expect(errors, [
      isA<TaskException>().having(
        (e) => e.message,
        'message',
        'Mediapipe error: Graph has errors.',
      ),
    ]);
    await task.dispose();
  });

  test('plugin errors become TaskException', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'create', message: 'Bad model.');
    });
    await expectLater(
      AudioClassifier.create(
        AudioClassifierOptions(modelBytes: Uint8List.fromList([1])),
      ),
      throwsA(
        isA<TaskException>().having((e) => e.message, 'message', 'Bad model.'),
      ),
    );
  });
}
