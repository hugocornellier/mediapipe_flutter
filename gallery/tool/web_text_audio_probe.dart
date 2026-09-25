// The text and audio tasks through the public Dart API in a browser, for
// tool/browser/test_browser.mjs --suite=text-audio, which compares every
// number here with Google's JavaScript run on the same page, runtime and
// inputs. With ?mic=1 it also classifies two seconds of microphone input,
// which the test feeds from a speech clip through Chrome's fake capture.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_audio/mediapipe_flutter_audio.dart';
import 'package:mediapipe_flutter_core/mediapipe_flutter_core.dart';
import 'package:mediapipe_flutter_text/mediapipe_flutter_text.dart';
import 'package:record/record.dart';

@JS('mediapipeTextAudioReport')
external set _report(JSAny? value);

/// Texts and classifier options, shared with the JavaScript side of the test.
const classifierCases = <(String, ClassifierOptions)>[
  ('Hello, world!', ClassifierOptions()),
  ('This was a terrible movie. I hated every minute.', ClassifierOptions()),
  ('Hello, world!', ClassifierOptions(maxResults: 1)),
  ('Hello, world!', ClassifierOptions(categoryDenylist: ['positive'])),
];
const embedderTexts = [
  'Hello, world!',
  'Hello there!',
  'The spacecraft landed on Mars.',
];
const languageTexts = [
  'Hello, world!',
  'Quiero agua, por favor.',
  'こんにちは、元気ですか？',
];
const clips = ['speech_16000_hz_mono.wav', 'speech_48000_hz_mono.wav'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Checking text and audio'))),
    ),
  );
  final report = <String, Object?>{};
  try {
    report['classifier'] = await _classifier();
    report['embedder'] = await _embedder();
    report['language'] = await _language();
    report['audio'] = await _audio();
    if (Uri.base.queryParameters['mic'] == '1') {
      report['microphone'] = await _microphone();
    }
    report['status'] = 'passed';
  } catch (error, stack) {
    report
      ..['status'] = 'failed'
      ..['error'] = '$error\n$stack';
  }
  _report = report.jsify();
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _rejects<T>(Future<Object?> Function() action) async {
  try {
    await action();
  } on Object catch (error) {
    _require(error is T, 'Expected $T, got $error');
    return;
  }
  throw StateError('Expected $T');
}

Future<Uint8List> _asset(String path) async {
  final data = await rootBundle.load(path);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

List<Object?> _categories(Iterable<Classifications> heads) => [
  for (final head in heads)
    [
      for (final c in head.categories)
        [c.index, c.score, c.categoryName, c.displayName],
    ],
];

Future<Object?> _classifier() async {
  final model = await _asset('assets/models/bert_classifier.tflite');
  final results = [];
  for (final (text, options) in classifierCases) {
    final task = await TextClassifier.create(
      TextClassifierOptions.fromAssetBuffer(model, classifierOptions: options),
    );
    try {
      results.add(_categories((await task.classify(text)).classifications));
    } finally {
      await task.dispose();
    }
  }
  // A model given as a URL, then ordered requests and disposal.
  final byPath = await TextClassifier.create(
    TextClassifierOptions.fromAssetPath(
      'assets/assets/models/bert_classifier.tflite',
    ),
  );
  final queued = await Future.wait([
    for (final (text, _) in classifierCases.take(2)) byPath.classify(text),
  ]);
  _require(
    _categories(queued.first.classifications).toString() ==
        results.first.toString(),
    'A model from a URL must match the same model from bytes.',
  );
  await byPath.dispose();
  await byPath.dispose();
  await _rejects<StateError>(() => byPath.classify('Hello'));
  await _rejects<TextTaskException>(
    () => TextClassifier.create(
      TextClassifierOptions.fromAssetBuffer(Uint8List.fromList([1, 2, 3])),
    ),
  );
  return results;
}

Future<Object?> _embedder() async {
  final model = await _asset('assets/models/universal_sentence_encoder.tflite');
  final result = <String, Object?>{};
  for (final quantize in [false, true]) {
    final task = await TextEmbedder.create(
      TextEmbedderOptions.fromAssetBuffer(
        model,
        embedderOptions: EmbedderOptions(
          l2Normalize: quantize,
          quantize: quantize,
        ),
      ),
    );
    try {
      final embeddings = [
        for (final text in embedderTexts)
          (await task.embed(text)).embeddings.single,
      ];
      result[quantize ? 'quantized' : 'float'] = {
        'values': [
          for (final e in embeddings)
            quantize
                ? e.quantizedEmbedding!.toList()
                : e.floatEmbedding!.toList(),
        ],
        'head': [embeddings.first.headIndex, embeddings.first.headName],
        'similarity': [
          await task.cosineSimilarity(embeddings[0], embeddings[1]),
          await task.cosineSimilarity(embeddings[0], embeddings[2]),
        ],
      };
    } finally {
      await task.dispose();
    }
  }
  return result;
}

Future<Object?> _language() async {
  final task = await LanguageDetector.create(
    LanguageDetectorOptions.fromAssetBuffer(
      await _asset('assets/models/language_detector.tflite'),
      classifierOptions: const ClassifierOptions(maxResults: 3),
    ),
  );
  try {
    return [
      for (final text in languageTexts)
        [
          for (final p in (await task.detect(text)).predictions)
            [p.languageCode, p.probability],
        ],
    ];
  } finally {
    await task.dispose();
  }
}

List<Object?> _chunks(List<AudioClassification> result) => [
  for (final chunk in result)
    [
      chunk.timestampMs,
      [
        for (final c in chunk.categories.take(5)) [c.index, c.score, c.name],
      ],
    ],
];

Future<Object?> _audio() async {
  final task = await AudioClassifier.create(
    AudioClassifierOptions(
      modelBytes: await _asset('assets/models/yamnet.tflite'),
    ),
  );
  final result = <String, Object?>{};
  try {
    for (final clip in clips) {
      result[clip] = _chunks(
        await task.classify(decodeWav(await _asset('assets/samples/$clip'))),
      );
    }
  } finally {
    await task.dispose();
  }
  await _rejects<StateError>(
    () => task.classify(
      AudioData(samples: Float32List(16000), sampleRate: 16000),
    ),
  );
  await _rejects<AudioClassifierException>(
    () => AudioClassifier.create(
      AudioClassifierOptions(modelBytes: Uint8List.fromList([1, 2, 3])),
    ),
  );
  return result;
}

/// Two seconds of microphone input at 16 kHz, classified like a clip.
Future<Object?> _microphone() async {
  const rate = 16000;
  final recorder = AudioRecorder();
  final bytes = BytesBuilder(copy: false);
  try {
    _require(await recorder.hasPermission(), 'Microphone access was denied.');
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: rate,
        numChannels: 1,
      ),
    );
    final done = Completer<void>();
    final subscription = stream.listen((chunk) {
      bytes.add(chunk);
      if (bytes.length >= rate * 2 * 2 && !done.isCompleted) done.complete();
    });
    await done.future.timeout(const Duration(seconds: 20));
    await subscription.cancel();
  } finally {
    await recorder.stop();
    await recorder.dispose();
  }
  final pcm = ByteData.sublistView(bytes.takeBytes());
  final samples = Float32List(pcm.lengthInBytes ~/ 2);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = pcm.getInt16(i * 2, Endian.little) / 32768;
  }
  final task = await AudioClassifier.create(
    AudioClassifierOptions(
      modelBytes: await _asset('assets/models/yamnet.tflite'),
    ),
  );
  try {
    return {
      'samples': samples.length,
      'chunks': _chunks(
        await task.classify(AudioData(samples: samples, sampleRate: 16000)),
      ),
    };
  } finally {
    await task.dispose();
  }
}
