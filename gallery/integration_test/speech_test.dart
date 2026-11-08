import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_audio/mediapipe_audio.dart';
import 'package:mediapipe_gallery/bundled_model_assets.dart';
import 'package:mediapipe_gallery/main.dart' show GalleryAssets;
import 'package:mediapipe_gallery/speech_page.dart' show speechSampleText;

import 'support/metal_memory.dart';

// The speech tasks inside the gallery app, beside the other runtimes:
// Google's per-family audio library must transcribe and speak as Google's
// Python API does on every platform. The package's native test covers every
// reference case (test/fixtures/official_speech_reference.json); this checks
// the app build, its model downloads and the runtime together. 32-bit
// Android refuses both tasks (largeModelNeeds64Bit). Browsers run
// tool/web_speech_probe.dart instead.
const _transcript = "Send a text to Mike, I'll be home late tomorrow.";

/// The fox utterance in Google's default voice: 74880 samples at 24 kHz and
/// each word with its start and end in seconds.
const _foxSamples = 74880;
const _foxRate = 24000;
const _foxWords = [
  ('The', 0.18, 0.42),
  ('quick', 0.42, 0.765),
  ('brown', 0.765, 0.915),
  ('fox', 0.915, 1.2),
  ('jumps', 1.2, 1.425),
  ('over', 1.425, 1.74),
  ('the', 1.74, 1.83),
  ('lazy', 1.83, 2.13),
  ('dog.', 2.13, 2.295),
];

/// The reference stream's text and the words its chunks time.
const _streamText =
    'Hello there. This is the second sentence, and it is longer. Third!';
const _streamWords = [
  'Hello',
  'there.',
  'This',
  'is',
  'the',
  'second',
  'sentence,',
  'and',
  'it',
  'is',
  'longer.',
  'Third!',
];

/// Another platform's build of Google's engine may round differently from
/// the macOS wheel the expectations came from: a model frame (80 ms at
/// 24 kHz) either way in length, and word times within a frame.
const _sampleSlack = 2 * 1920;
const _secondsSlack = 0.08;

/// What the GPU run must hold on Metal beyond the CPU run: far below the
/// model's weights, and far above what the app draws between two runs.
const _metalProof = 32 * 1024 * 1024;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Audio Transcriber writes out the clip as Google\'s Python '
      'API does', (tester) async {
    await tester.runAsync(() async {
      final assets = await GalleryAssets.unpack();
      if (!assets.bundledTasks.contains('audio_transcriber')) {
        markTestSkipped('This build bundles no Audio Transcriber.');
        return;
      }
      final capabilities = await queryAudioTranscriberCapabilities();
      if (!capabilities.isSupported) {
        await expectLater(
          AudioTranscriber.create(
            AudioTranscriberOptions(model: AudioModels.parakeetTdtV3),
          ),
          throwsA(isA<RuntimeUnavailableException>()),
        );
        markTestSkipped(
          'Audio Transcriber: ${capabilities.unavailableReasons}',
        );
        return;
      }
      // Google's 615 MB model, downloaded and verified once into the model
      // cache.
      final modelPath = await GalleryAssets.downloadedModelPath(
        AudioModels.parakeetTdtV3,
      );
      final audio = decodeWav(
        await loadAssetBytes('assets/samples/speech_16000_hz_mono.wav'),
      );
      final task = await AudioTranscriber.create(
        AudioTranscriberOptions(modelPath: modelPath),
      );
      try {
        final result = await task.transcribe(audio);
        expect(result.text, _transcript);
        final segment = result.segments.single;
        expect(segment.isFinal, isTrue);
        expect(segment.fromTimestampMilliseconds, 0);
        expect(segment.toTimestampMilliseconds, closeTo(4272, 100));

        // The same clip as a stream of one-second blocks: nothing final
        // until the stream ends, then the same sentence.
        final calls = <TranscriptionSegment>[];
        for (var start = 0; start < audio.samples.length; start += 16000) {
          final part = AudioData(
            samples: Float32List.sublistView(
              audio.samples,
              start,
              math.min(start + 16000, audio.samples.length),
            ),
            sampleRate: audio.sampleRate,
          );
          calls.addAll(
            (await task.transcribe(part, endOfStream: false)).segments,
          );
        }
        final finish = await task.finishStream();
        expect(
          [...calls, ...finish.segments].last.isFinal,
          isTrue,
          reason: 'a stream ends on a final segment',
        );
        expect(
          AudioTranscriberResult([...calls, ...finish.segments]).text,
          _transcript,
        );
      } finally {
        await task.dispose();
      }
    });
  });

  // Google's library accepts the GPU delegate and can stay on the CPU, as its
  // Text to Speech does with Phonon, and the answer reads the same: so the
  // proof is the memory the task holds on Metal.
  testWidgets('Audio Transcriber runs on the GPU only where it does the work', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final assets = await GalleryAssets.unpack();
      if (!assets.bundledTasks.contains('audio_transcriber')) {
        markTestSkipped('This build bundles no Audio Transcriber.');
        return;
      }
      final capabilities = await queryAudioTranscriberCapabilities();
      if (!capabilities.supportedDelegates.contains(Delegate.gpu)) {
        await expectLater(
          AudioTranscriber.create(
            AudioTranscriberOptions(
              model: AudioModels.parakeetTdtV3,
              delegate: Delegate.gpu,
            ),
          ),
          throwsA(isA<RuntimeUnavailableException>()),
        );
        markTestSkipped(
          'Audio Transcriber GPU: '
          '${capabilities.unavailableReasons[Delegate.gpu]}',
        );
        return;
      }
      final modelPath = await GalleryAssets.downloadedModelPath(
        AudioModels.parakeetTdtV3,
      );
      final audio = decodeWav(
        await loadAssetBytes('assets/samples/speech_16000_hz_mono.wav'),
      );
      Future<int> grown(Delegate delegate) async {
        final before = metalAllocatedBytes();
        final task = await AudioTranscriber.create(
          AudioTranscriberOptions(modelPath: modelPath, delegate: delegate),
        );
        try {
          expect((await task.transcribe(audio)).text, _transcript);
          return metalAllocatedBytes() - before;
        } finally {
          await task.dispose();
        }
      }

      final onCpu = await grown(Delegate.cpu);
      final onGpu = await grown(Delegate.gpu);
      // ignore: avoid_print
      print('Metal bytes the transcriber added: CPU $onCpu, GPU $onGpu');
      expect(onGpu, greaterThan(onCpu + _metalProof));
    });
  });

  testWidgets('Text to Speech speaks as Google\'s Python API does', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final assets = await GalleryAssets.unpack();
      if (!assets.bundledTasks.contains('text_to_speech')) {
        markTestSkipped('This build bundles no Text to Speech.');
        return;
      }
      final capabilities = await queryTextToSpeechCapabilities();
      if (!capabilities.isSupported) {
        await expectLater(
          TextToSpeech.create(TextToSpeechOptions(model: AudioModels.phonon)),
          throwsA(isA<RuntimeUnavailableException>()),
        );
        markTestSkipped('Text to Speech: ${capabilities.unavailableReasons}');
        return;
      }
      // Google's 87 MB model, downloaded and verified once into the model
      // cache.
      final task = await TextToSpeech.create(
        TextToSpeechOptions(
          modelPath: await GalleryAssets.downloadedModelPath(
            AudioModels.phonon,
          ),
        ),
      );
      try {
        final voices = await task.listVoices();
        expect(voices, hasLength(5));
        expect(voices.first.voiceId, 'freya');
        expect(voices.first.sampleRateHz, _foxRate);

        final fox = await task.synthesize(speechSampleText);
        expect(fox.sampleRateHz, _foxRate);
        expect(fox.samples.length, closeTo(_foxSamples, _sampleSlack));
        expect(fox.isFinal, isTrue);
        expect(
          [for (final w in fox.wordTimestamps) w.word],
          [for (final (word, _, _) in _foxWords) word],
        );
        for (final (i, word) in fox.wordTimestamps.indexed) {
          final (name, start, end) = _foxWords[i];
          expect(speechSampleText.substring(word.start, word.end), name);
          expect(word.startSeconds, closeTo(start, _secondsSlack));
          expect(word.endSeconds, closeTo(end, _secondsSlack));
        }
        final peak = fox.samples.fold(0.0, (m, s) => math.max(m, s.abs()));
        expect(peak, closeTo(0.576448, 0.05));

        // A short stream: chunks in order, only the last one final, timing
        // every word of the text.
        final chunks = await task.synthesizeStream(_streamText).toList();
        expect(chunks, isNotEmpty);
        for (final (i, chunk) in chunks.indexed) {
          expect(chunk.chunkIndex, i);
          expect(chunk.isFinal, i == chunks.length - 1);
          expect(chunk.sampleRateHz, _foxRate);
        }
        expect([
          for (final chunk in chunks)
            for (final w in chunk.wordTimestamps) w.word,
        ], _streamWords);
      } finally {
        await task.dispose();
      }
    });
  });
}
