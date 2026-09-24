import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_core/src/native_assets/tasks_runtime.dart'
    show tasksRuntimeWheel;
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

/// Google's result on this host when CI prepared one with
/// tool/prepare_audio_reference.py; otherwise the checked-in macOS reference.
/// A missing or modified same-host reference fails instead of falling back.
Map<String, dynamic> _loadReference() {
  final baselineBytes = File(
    '$_fixtures/official_reference.json',
  ).readAsBytesSync();
  final baseline =
      jsonDecode(utf8.decode(baselineBytes)) as Map<String, dynamic>;
  final directory = Platform.environment['MEDIAPIPE_AUDIO_REFERENCE_DIR'];
  if (directory == null) return baseline;
  final root = Directory(directory).absolute.uri;
  final bytes = File.fromUri(
    root.resolve('official_reference.json'),
  ).readAsBytesSync();
  final reference = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final receipt =
      jsonDecode(
            File.fromUri(root.resolve('provenance.json')).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final wheel = tasksRuntimeWheel(
    Abi.current().toString().replaceFirst('_', '/'),
  );
  final runtime = 'mediapipe==${wheel?.version}';
  if (wheel == null ||
      receipt['source'] != 'official-python-api' ||
      receipt['runtime'] != runtime ||
      receipt['library_sha256'] != wheel.librarySha256 ||
      receipt['wheel_sha256'] != wheel.wheelSha256 ||
      receipt['reference_sha256'] != sha256.convert(bytes).toString() ||
      receipt['baseline_sha256'] != sha256.convert(baselineBytes).toString() ||
      reference['runtime'] != runtime ||
      reference['model_sha256'] != baseline['model_sha256'] ||
      jsonEncode((reference['clips'] as Map).keys.toList()) !=
          jsonEncode((baseline['clips'] as Map).keys.toList())) {
    throw StateError('Invalid same-host official audio reference');
  }
  return reference;
}

void main() {
  final reference = _loadReference();
  final clips = reference['clips'] as Map<String, dynamic>;

  setUpAll(() {
    expect(
      sha256.convert(File(_model).readAsBytesSync()).toString(),
      yamnetSha256,
    );
    expect(reference['model_sha256'], yamnetSha256);
  });

  for (final MapEntry(key: clip, value: expected) in clips.entries) {
    test('$clip matches the official result, chunk by chunk', () async {
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
