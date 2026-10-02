// Needs Flutter's test binding; `dart test` skips it (tag `flutter`).
@Tags(['flutter'])
library;

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_audio/mediapipe_audio.dart';
import 'package:mediapipe_audio/mediapipe_audio_android.dart';

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
