import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_audio/mediapipe_flutter_audio.dart';
import 'package:mediapipe_flutter_audio/models.dart';
import 'package:mediapipe_flutter_audio/src/third_party/mediapipe/audio_classifier_bindings.dart'
    as abi;
import 'package:test/test.dart';

const _fixtures = 'test/fixtures';
const _model = 'models/yamnet.tflite';

/// The same runtime, model and samples as Google's reference, so scores agree
/// to rounding (the reference rounds to six places).
const _scoreDelta = 1e-5;

void main() {
  final reference =
      jsonDecode(File('$_fixtures/official_reference.json').readAsStringSync())
          as Map<String, dynamic>;
  final clips = reference['clips'] as Map<String, dynamic>;

  setUpAll(() {
    expect(
      sha256.convert(File(_model).readAsBytesSync()).toString(),
      yamnetSha256,
    );
    expect(reference['model_sha256'], yamnetSha256);
  });

  for (final MapEntry(key: clip, value: expected) in clips.entries) {
    test('$clip matches the official 1.0.1 result, chunk by chunk', () async {
      final task = await AudioClassifier.create(
        AudioClassifierOptions(modelPath: _model, maxResults: 3),
      );
      addTearDown(task.dispose);
      final audio = decodeWav(File('$_fixtures/$clip').readAsBytesSync());
      final chunks = await task.classify(audio);
      final want = (expected as List).cast<Map<String, dynamic>>();
      expect(chunks, hasLength(want.length));
      for (final (i, chunk) in chunks.indexed) {
        expect(chunk.timestampMs, want[i]['timestamp_ms']);
        final top = {
          for (final [name as String, score as num]
              in (want[i]['top'] as List).cast<List>())
            name: score.toDouble(),
        };
        // Google's scores for these names, in its order; categories with
        // equal scores may come in either order.
        expect(chunk.categories.map((c) => c.name).toSet(), top.keys.toSet());
        for (final category in chunk.categories) {
          expect(category.score, closeTo(top[category.name]!, _scoreDelta));
        }
        final scores = [for (final c in chunk.categories) c.score];
        expect(
          scores,
          orderedEquals([...scores]..sort((x, y) => y.compareTo(x))),
        );
      }
    });
  }

  test('model bytes, repeated calls and max results agree', () async {
    final task = await AudioClassifier.create(
      AudioClassifierOptions(
        modelBytes: File(_model).readAsBytesSync(),
        maxResults: 1,
      ),
    );
    addTearDown(task.dispose);
    final audio = decodeWav(
      File('$_fixtures/speech_16000_hz_mono.wav').readAsBytesSync(),
    );
    final [first, second] = await Future.wait([
      task.classify(audio),
      task.classify(audio),
    ]);
    expect(first.first.categories.single.name, 'Speech');
    expect(
      second.first.categories.single.score,
      first.first.categories.single.score,
    );
  });

  test('score threshold drops weak categories', () async {
    final task = await AudioClassifier.create(
      AudioClassifierOptions(modelPath: _model, scoreThreshold: 0.5),
    );
    addTearDown(task.dispose);
    final chunks = await task.classify(
      decodeWav(File('$_fixtures/speech_16000_hz_mono.wav').readAsBytesSync()),
    );
    for (final chunk in chunks) {
      for (final category in chunk.categories) {
        expect(category.score, greaterThanOrEqualTo(0.5));
      }
    }
  });

  test('errors come back as exceptions, and disposal is final', () async {
    await expectLater(
      AudioClassifier.create(
        AudioClassifierOptions(modelBytes: Uint8List.fromList([1, 2, 3])),
      ),
      throwsA(isA<AudioClassifierException>()),
    );
    final task = await AudioClassifier.create(
      AudioClassifierOptions(modelPath: _model),
    );
    final closing = task.dispose();
    expect(identical(closing, task.dispose()), isTrue);
    await closing;
    expect(
      () => task.classify(
        AudioData(samples: Float32List(16000), sampleRate: 16000),
      ),
      throwsStateError,
    );
    expect(() => decodeWav(Uint8List(4)), throwsFormatException);
  });

  test('struct layouts match the official 1.0.1 ctypes', () {
    expect(sizeOf<abi.MpBaseOptions>(), 72);
    expect(sizeOf<abi.MpClassifierOptions>(), 48);
    expect(sizeOf<abi.MpAudioClassifierOptions>(), 136);
    expect(sizeOf<abi.MpAudioData>(), 32);
    expect(sizeOf<abi.MpClassificationResult>(), 32);
    expect(sizeOf<abi.MpClassifications>(), 24);
    expect(sizeOf<abi.MpCategory>(), 24);
    expect(sizeOf<abi.MpAudioClassifierResult>(), 16);
  });
}
