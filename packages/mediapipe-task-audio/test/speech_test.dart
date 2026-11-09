import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mediapipe_audio/mediapipe_audio.dart';
import 'package:mediapipe_audio/src/audio_task_backend.dart'
    show audioTranscriberOpener, browserOnMac;
import 'package:mediapipe_audio/src/utf16_indices.dart';
import 'package:mediapipe_audio/src/third_party/mediapipe/audio_transcriber_bindings.dart'
    as asr;
import 'package:mediapipe_audio/src/third_party/mediapipe/text_to_speech_bindings.dart'
    as tts;
import 'package:mediapipe_core/src/native_assets/reference_wheels.dart'
    show releaseReferenceWheel;
import 'package:test/test.dart';

import 'support/metal_memory.dart';
import 'support/same_host_reference.dart';

const _fixtures = 'test/fixtures';
final _transcriberModel =
    'models/${Uri.parse(AudioModels.parakeetTdtV3.url).pathSegments.last}';
final _ttsModel =
    'models/${Uri.parse(AudioModels.phonon.url).pathSegments.last}';

final _kokoroModel =
    'models/${Uri.parse(AudioModels.kokoro.url).pathSegments.last}';

/// The models CI downloads for this runner, which their tests must not skip
/// without: family.yaml names them.
final _requiredModels =
    (Platform.environment['MEDIAPIPE_REQUIRED_MODELS'] ?? '').split(' ');

/// Google's word times, rounded to four places in the reference.
const _secondsDelta = 1e-3;

/// More than Metal's own bookkeeping: the transcriber on the GPU holds hundreds
/// of megabytes there.
const _metalProof = 32 * 1024 * 1024;

/// The family library and the reference wheel's single library are separate
/// builds of Google's 1.2.2 release, so the audio gets a small bound: each
/// 100 ms window's RMS and the peak may move by this much.
const _levelDelta = 2e-3;

void main() {
  final reference = loadSameHostReference(
    'official_speech_reference.json',
    prefix: '',
    cases: 'cases',
    environment: 'MEDIAPIPE_SPEECH_REFERENCE_DIR',
    wheel: releaseReferenceWheel,
  );
  final cases = reference['cases'] as Map<String, dynamic>;
  final transcriberCases = cases['transcriber'] as Map<String, dynamic>;
  final speech = cases['text_to_speech'] as Map<String, dynamic>;
  final missingTranscriber = _missing(
    'Parakeet',
    _transcriberModel,
    'parakeet_tdt_v3',
  );
  final missingKokoro = _missing('Kokoro', _kokoroModel, 'kokoro');
  final missingTts = _missing('Phonon', _ttsModel, 'phonon');

  test('the reference names the pinned models', () {
    expect(reference['models'], {
      'parakeet_tdt_0.6b_v3_5s_i8_stateful.litertlm':
          AudioModels.parakeetTdtV3.sha256,
      'phonon_int8.litertlm': AudioModels.phonon.sha256,
    });
  });

  group('AudioTranscriber', () {
    setUpAll(() {
      if (missingTranscriber != null) return;
      expect(
        sha256.convert(File(_transcriberModel).readAsBytesSync()).toString(),
        AudioModels.parakeetTdtV3.sha256,
      );
    });

    for (final MapEntry(key: name, value: expected as Map<String, dynamic>)
        in transcriberCases.entries) {
      test(
        '$name matches Google\'s Python API',
        skip: missingTranscriber,
        () async {
          final task = await AudioTranscriber.create(
            AudioTranscriberOptions(
              modelPath: _transcriberModel,
              sampleRateHz: expected['rate'] as int,
              enableInterimResults: expected['interim_results'] as bool,
            ),
          );
          addTearDown(task.dispose);
          final audio = decodeWav(
            File('$_fixtures/${expected['clip']}').readAsBytesSync(),
          );
          final block = expected['block_frames'] as int?;
          final calls = <List<Map<String, Object>>>[];
          if (block == null) {
            calls.add(_segments(await task.transcribe(audio)));
          } else {
            for (var start = 0; start < audio.samples.length; start += block) {
              final part = AudioData(
                samples: Float32List.sublistView(
                  audio.samples,
                  start,
                  math.min(start + block, audio.samples.length),
                ),
                sampleRate: audio.sampleRate,
              );
              calls.add(
                _segments(await task.transcribe(part, endOfStream: false)),
              );
            }
          }
          expect(calls, expected['calls']);
          expect(_segments(await task.finishStream()), expected['finish']);
        },
      );
    }

    test(
      'averages channels and joins segments as Google\'s text does',
      skip: missingTranscriber,
      () async {
        final task = await AudioTranscriber.create(
          AudioTranscriberOptions(modelPath: _transcriberModel),
        );
        addTearDown(task.dispose);
        final mono = decodeWav(
          File('$_fixtures/speech_16000_hz_mono.wav').readAsBytesSync(),
        );
        final stereo = Float32List(mono.samples.length * 2);
        for (var i = 0; i < mono.samples.length; i++) {
          stereo[2 * i] = stereo[2 * i + 1] = mono.samples[i];
        }
        final result = await task.transcribe(
          AudioData(samples: stereo, sampleRate: 16000, channels: 2),
        );
        final expected =
            (transcriberCases['speech-16k']['calls'] as List).single as List;
        expect(_segments(result), expected);
        expect(result.text, (expected.single as Map)['transcript']);
        await expectLater(
          task.transcribe(AudioData(samples: mono.samples, sampleRate: 48000)),
          throwsArgumentError,
        );
        await task.prewarm();
        await task.dispose();
        await task.dispose();
        expect(() => task.transcribe(mono), throwsStateError);
      },
    );

    // Google's library accepts the GPU delegate and can stay on the CPU, as
    // its Text to Speech does with Phonon, and the answer reads the same: so
    // the proof is the memory the task holds on Metal. The package job runs it
    // on each macOS version the capabilities claim.
    test(
      'runs on the GPU on this Mac',
      skip: Abi.current() != Abi.macosArm64
          ? 'Only on a Mac.'
          : missingTranscriber,
      timeout: const Timeout(Duration(minutes: 10)),
      () async {
        expect(
          (await queryAudioTranscriberCapabilities()).supportedDelegates,
          contains(Delegate.gpu),
        );
        final audio = decodeWav(
          File('$_fixtures/speech_16000_hz_mono.wav').readAsBytesSync(),
        );
        final expected =
            (transcriberCases['speech-16k']['calls'] as List).single as List;
        Future<int> grown(Delegate delegate) async {
          final before = metalAllocatedBytes();
          final task = await AudioTranscriber.create(
            AudioTranscriberOptions(
              modelPath: _transcriberModel,
              delegate: delegate,
            ),
          );
          try {
            final result = await task.transcribe(audio);
            expect(result.text, (expected.single as Map)['transcript']);
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
      },
    );
  });

  group('TextToSpeech', () {
    late TextToSpeech task;
    setUpAll(() async {
      if (missingTts != null) return;
      expect(
        sha256.convert(File(_ttsModel).readAsBytesSync()).toString(),
        AudioModels.phonon.sha256,
      );
      task = await TextToSpeech.create(
        TextToSpeechOptions(modelPath: _ttsModel),
      );
    });
    tearDownAll(() async {
      if (missingTts == null) await task.dispose();
    });

    test('lists Google\'s voices', skip: missingTts, () async {
      expect([
        for (final voice in await task.listVoices())
          {
            'voice_id': voice.voiceId,
            'display_name': voice.displayName,
            'locale': voice.locale,
            'sample_rate_hz': voice.sampleRateHz,
            'is_downloaded': voice.isDownloaded,
          },
      ], speech['voices']);
    });

    final utterances = speech['utterances'] as Map<String, dynamic>;
    for (final MapEntry(key: name, value: expected as Map<String, dynamic>)
        in utterances.entries) {
      test('$name matches Google\'s Python API', skip: missingTts, () async {
        final text = expected['text'] as String;
        _expectAudio(
          await task.synthesize(
            text,
            voiceId: expected['voice_id'] as String?,
            locale: expected['locale'] as String?,
          ),
          text,
          expected,
        );
      });
    }

    test(
      'a stream\'s chunks match Google\'s Python API',
      skip: missingTts,
      () async {
        final stream = speech['stream'] as Map<String, dynamic>;
        final text = stream['text'] as String;
        final chunks = await task.synthesizeStream(text).toList();
        final expected = (stream['chunks'] as List)
            .cast<Map<String, dynamic>>();
        expect(chunks, hasLength(expected.length));
        for (final (i, chunk) in chunks.indexed) {
          expect(chunk.chunkIndex, expected[i]['chunk_index']);
          expect(chunk.isFinal, expected[i]['is_final']);
          _expectAudio(chunk, text, expected[i]);
        }
      },
    );

    test(
      'cancelling a stream stops it, and the task still answers',
      skip: missingTts,
      () async {
        final text = (speech['stream'] as Map)['text'] as String;
        var received = 0;
        await for (final chunk in task.synthesizeStream(text)) {
          expect(chunk.chunkIndex, 0);
          received++;
          break;
        }
        expect(received, 1);
        final fox = utterances['fox'] as Map<String, dynamic>;
        _expectAudio(
          await task.synthesize(fox['text'] as String),
          fox['text'] as String,
          fox,
        );
      },
    );

    test('speaks at the options\' rate', skip: missingTts, () async {
      final fast = speech['fast'] as Map<String, dynamic>;
      final quick = await TextToSpeech.create(
        TextToSpeechOptions(
          modelPath: _ttsModel,
          speakingRate: (fast['speaking_rate'] as num).toDouble(),
        ),
      );
      addTearDown(quick.dispose);
      final text = fast['text'] as String;
      _expectAudio(await quick.synthesize(text), text, fast);
    });

    // Google's task accepts the GPU delegate for Phonon and runs it on the
    // CPU, holding nothing on Metal: its bundle marks no section for the GPU.
    test('refuses the GPU for Phonon', skip: missingTts, () async {
      await expectLater(
        TextToSpeech.create(
          TextToSpeechOptions(modelPath: _ttsModel, delegate: Delegate.gpu),
        ),
        throwsA(
          isA<RuntimeUnavailableException>().having(
            (error) => error.fix,
            'fix',
            Abi.current() == Abi.macosArm64
                ? contains('marks none')
                : contains('proved'),
          ),
        ),
      );
    });

    // Kokoro's vocoder runs on Metal, which the answer alone cannot show
    // (the GPU's audio differs from the CPU's in its phase, not its words):
    // so the proof is the memory the task holds there.
    test(
      'runs Kokoro on the GPU on this Mac',
      skip: Abi.current() != Abi.macosArm64 ? 'Only on a Mac.' : missingKokoro,
      timeout: const Timeout(Duration(minutes: 10)),
      () async {
        expect(
          sha256.convert(File(_kokoroModel).readAsBytesSync()).toString(),
          AudioModels.kokoro.sha256,
        );
        expect(
          (await queryTextToSpeechCapabilities()).supportedDelegates,
          contains(Delegate.gpu),
        );
        const text = 'The quick brown fox jumps over the lazy dog.';
        Future<(int, TextToSpeechResult)> run(Delegate delegate) async {
          final before = metalAllocatedBytes();
          final kokoro = await TextToSpeech.create(
            TextToSpeechOptions(modelPath: _kokoroModel, delegate: delegate),
          );
          try {
            final speech = await kokoro.synthesize(text);
            return (metalAllocatedBytes() - before, speech);
          } finally {
            await kokoro.dispose();
          }
        }

        final (onCpu, cpu) = await run(Delegate.cpu);
        final (onGpu, gpu) = await run(Delegate.gpu);
        // ignore: avoid_print
        print('Metal bytes Kokoro added: CPU $onCpu, GPU $onGpu');
        expect(onCpu, lessThan(_metalProof));
        expect(onGpu, greaterThan(onCpu + _metalProof));
        // The acoustic model runs on the CPU either way, so the words take
        // the same time; the GPU's FP16 vocoder gives each 100 ms window
        // nearly the same level.
        expect(gpu.sampleRateHz, cpu.sampleRateHz);
        expect(gpu.samples.length, cpu.samples.length);
        expect(cpu.samples.length, greaterThan(cpu.sampleRateHz));
        final window = cpu.sampleRateHz ~/ 10;
        for (
          var start = 0;
          start + window <= cpu.samples.length;
          start += window
        ) {
          expect(
            _windowRms(gpu.samples, start, window),
            closeTo(_windowRms(cpu.samples, start, window), 0.02),
            reason: 'window at $start',
          );
        }
        expect(
          _windowRms(gpu.samples, 0, gpu.samples.length),
          greaterThan(0.01),
        );
      },
    );

    test('a disposed task refuses calls', skip: missingTts, () async {
      final other = await TextToSpeech.create(
        TextToSpeechOptions(modelPath: _ttsModel),
      );
      await other.dispose();
      await other.dispose();
      expect(() => other.synthesize('Hello.'), throwsStateError);
      expect(() => other.synthesizeStream('Hello.'), throwsStateError);
    });
  });

  test('options refuse values Google rejects', () {
    expect(() => AudioTranscriberOptions(sampleRateHz: 0), throwsArgumentError);
    expect(() => TextToSpeechOptions(speakingRate: 0), throwsArgumentError);
    expect(() => TextToSpeechOptions(speakingRate: 4.5), throwsArgumentError);
    // Google's guide lists Kokoro's buckets as 0, 64, 128 and 256.
    TextToSpeechOptions kokoro(int bucket) =>
        TextToSpeechOptions(modelPath: 'kokoro.litertlm', targetBucket: bucket);
    for (final bucket in [-1, 32, 512]) {
      expect(
        () => kokoro(bucket),
        throwsA(
          isA<ArgumentError>().having((e) => e.name, 'name', 'targetBucket'),
        ),
      );
    }
    for (final bucket in [0, 64, 128, 256]) {
      expect(kokoro(bucket).targetBucket, bucket);
    }
  });

  test('each speech task offers the GPU only where it is proved', () async {
    expect((await queryTextToSpeechCapabilities()).supportedDelegates, {
      Delegate.cpu,
      if (Abi.current() == Abi.macosArm64) Delegate.gpu,
    });
    const mac = TaskPlatform(
      operatingSystem: 'macos',
      architecture: 'arm64',
      version: '15.0',
    );
    expect(audioTranscriberCapabilitiesForPlatform(mac).supportedDelegates, {
      Delegate.cpu,
      Delegate.gpu,
    });
    expect(textToSpeechCapabilitiesForPlatform(mac).supportedDelegates, {
      Delegate.cpu,
      Delegate.gpu,
    });
    // Kokoro has never run on macOS 14, which CI no longer runs.
    const mac14 = TaskPlatform(
      operatingSystem: 'macos',
      architecture: 'arm64',
      version: '14.0',
    );
    expect(textToSpeechCapabilitiesForPlatform(mac14).supportedDelegates, {
      Delegate.cpu,
    });
    expect(audioTranscriberCapabilitiesForPlatform(mac14).supportedDelegates, {
      Delegate.cpu,
      Delegate.gpu,
    });
    for (final platform in const [
      TaskPlatform(operatingSystem: 'linux', architecture: 'x64'),
      TaskPlatform(operatingSystem: 'windows', architecture: 'x64'),
      TaskPlatform(operatingSystem: 'android', architecture: 'arm64'),
      TaskPlatform(
        operatingSystem: 'ios',
        architecture: 'arm64',
        version: '17.0',
      ),
    ]) {
      final speech = textToSpeechCapabilitiesForPlatform(platform);
      expect(speech.supportedDelegates, {Delegate.cpu}, reason: '$platform');
      expect(
        speech.unavailableReasons[Delegate.gpu],
        allOf(contains('proved'), contains('Kokoro')),
        reason: '$platform',
      );
      final capabilities = audioTranscriberCapabilitiesForPlatform(platform);
      expect(capabilities.supportedDelegates, {
        Delegate.cpu,
      }, reason: '$platform');
      expect(
        capabilities.unavailableReasons[Delegate.gpu],
        contains('proved'),
        reason: '$platform',
      );
    }
    const browser = TaskPlatform(operatingSystem: 'web', architecture: 'wasm');
    expect(audioTranscriberCapabilitiesForPlatform(browser).isSupported, false);
    expect(textToSpeechCapabilitiesForPlatform(browser).isSupported, false);
    const arm32 = TaskPlatform(operatingSystem: 'android', architecture: 'arm');
    expect(textToSpeechCapabilitiesForPlatform(arm32).isSupported, false);
  });

  test('a browser serves the speech tasks once the web plugin registers', () {
    // TaskPlatform.current on the web.
    const browser = TaskPlatform(
      operatingSystem: 'web',
      architecture: 'unknown',
    );
    expect(audioTranscriberCapabilitiesForPlatform(browser).isSupported, false);
    expect(textToSpeechCapabilitiesForPlatform(browser).isSupported, false);
    audioTranscriberOpener = (_) => throw UnimplementedError();
    addTearDown(() => audioTranscriberOpener = null);
    expect(audioTranscriberCapabilitiesForPlatform(browser).isSupported, true);
    expect(textToSpeechCapabilitiesForPlatform(browser).isSupported, true);
    for (final capabilities in [
      audioTranscriberCapabilitiesForPlatform(browser),
      textToSpeechCapabilitiesForPlatform(browser),
    ]) {
      expect(capabilities.supportedDelegates, {Delegate.cpu});
    }
    expect(
      audioTranscriberCapabilitiesForPlatform(
        browser,
      ).unavailableReasons[Delegate.gpu],
      contains('no WebGPU adapter'),
    );
    // A software adapter gets the same answer.
    const software = TaskPlatform(
      operatingSystem: 'web',
      architecture: 'unknown',
      gpu: 'WebGPU google swiftshader',
    );
    expect(
      audioTranscriberCapabilitiesForPlatform(software).supportedDelegates,
      {Delegate.cpu},
    );
    const hardware = TaskPlatform(
      operatingSystem: 'web',
      architecture: 'unknown',
      gpu: 'WebGPU apple metal-3',
      browserEngine: BrowserEngine.blink,
    );
    expect(textToSpeechCapabilitiesForPlatform(hardware).supportedDelegates, {
      Delegate.cpu,
    });
    expect(
      textToSpeechCapabilitiesForPlatform(
        hardware,
      ).unavailableReasons[Delegate.gpu],
      contains('in a browser yet'),
    );
  });

  group('the browser GPU delegate, offered only where a test proved it', () {
    setUp(() {
      audioTranscriberOpener = (_) => throw UnimplementedError();
      browserOnMac = true;
      addTearDown(() {
        audioTranscriberOpener = null;
        browserOnMac = false;
      });
    });

    TaskCapabilities on(String? gpu, BrowserEngine? engine) =>
        audioTranscriberCapabilitiesForPlatform(
          TaskPlatform(
            operatingSystem: 'web',
            architecture: 'unknown',
            gpu: gpu,
            browserEngine: engine,
          ),
        );

    test("Chromium and WebKit on a Mac's Apple adapter", () {
      for (final (gpu, engine) in const [
        ('WebGPU apple metal-3', BrowserEngine.blink),
        ('WebGPU apple apple apple', BrowserEngine.webkit),
      ]) {
        expect(on(gpu, engine).supportedDelegates, {
          Delegate.cpu,
          Delegate.gpu,
        }, reason: gpu);
      }
    });

    test('no other browser or adapter, and the refusal says why', () {
      for (final (gpu, engine) in const [
        ('WebGPU apple metal-3', BrowserEngine.gecko),
        ('WebGPU apple metal-3', null),
        ('WebGPU intel gen-9', BrowserEngine.blink),
        ('WebGPU amd gcn-5', BrowserEngine.webkit),
        ('WebGPU nvidia ga100', BrowserEngine.blink),
        ('WebGPU applesauce metal-3', BrowserEngine.blink),
      ]) {
        final capabilities = on(gpu, engine);
        expect(capabilities.supportedDelegates, {Delegate.cpu}, reason: gpu);
        final why = capabilities.unavailableReasons[Delegate.gpu];
        expect(why, contains('a test proved'), reason: gpu);
        expect(why, contains("a Mac's Apple adapter"), reason: gpu);
        expect(why, contains(gpu), reason: gpu);
      }
    });

    test("a phone or tablet naming a Mac's adapter", () {
      browserOnMac = false;
      for (final (gpu, engine) in const [
        ('WebGPU apple metal-3', BrowserEngine.blink),
        ('WebGPU apple apple apple', BrowserEngine.webkit),
        ('WebGPU nvidia ga100', BrowserEngine.blink),
        ('WebGPU qualcomm adreno-7xx', BrowserEngine.blink),
      ]) {
        final capabilities = on(gpu, engine);
        expect(capabilities.supportedDelegates, {Delegate.cpu}, reason: gpu);
        expect(
          capabilities.unavailableReasons[Delegate.gpu],
          contains('a test proved'),
          reason: gpu,
        );
      }
    });

    test('a Mac without a hardware adapter', () {
      for (final gpu in const [null, 'WebGPU apple swiftshader']) {
        final capabilities = on(gpu, BrowserEngine.blink);
        expect(capabilities.supportedDelegates, {Delegate.cpu}, reason: gpu);
        expect(
          capabilities.unavailableReasons[Delegate.gpu],
          contains('needs a hardware WebGPU adapter'),
          reason: gpu,
        );
      }
    });
  });

  test('UTF-8 offsets become UTF-16 indices', () {
    const text = 'Café 😀 done';
    final indices = utf16Indices(text);
    expect(indices, hasLength(utf8.encode(text).length + 1));
    int at(String prefix) => indices[utf8.encode(prefix).length];
    expect(at('Caf'), 3);
    expect(at('Café'), 4);
    expect(at('Café 😀'), 'Café 😀'.length);
    expect(at(text), text.length);
  });

  test('struct layouts match the 1.2.2 C headers', () {
    expect(sizeOf<asr.MpAudioTranscriberOptions>(), 104);
    expect(sizeOf<asr.MpTranscriptionSegment>(), 32);
    expect(sizeOf<asr.MpAudioTranscriberResult>(), 16);
    expect(sizeOf<tts.MpTextToSpeechOptions>(), 104);
    expect(sizeOf<tts.MpTextToSpeechSynthesisOptions>(), 16);
    expect(sizeOf<tts.MpTextToSpeechVoiceInfo>(), 32);
    expect(sizeOf<tts.MpTextToSpeechVoiceList>(), 16);
    expect(sizeOf<tts.MpTextToSpeechWordTimestamp>(), 24);
    expect(sizeOf<tts.MpTextToSpeechAudioResult>(), 40);
  });
}

/// Why a test needing [path] skips, or null when it runs: always on a CI job
/// that downloads [name], where a missing file fails the test instead.
String? _missing(String model, String path, String name) =>
    File(path).existsSync() || _requiredModels.contains(name)
    ? null
    : 'No $model model at $path; run dart tool/download_models.dart $name.';

List<Map<String, Object>> _segments(AudioTranscriberResult result) => [
  for (final segment in result.segments)
    {
      'transcript': segment.transcript,
      'is_final': segment.isFinal,
      'from_ms': segment.fromTimestampMilliseconds,
      'to_ms': segment.toTimestampMilliseconds,
    },
];

/// [result] against Google's: the same length and rate, the same words at
/// the same places in [text] (Google's UTF-8 byte offsets, which the package
/// turns into UTF-16 indices), and the same level in every window.
void _expectAudio(
  TextToSpeechResult result,
  String text,
  Map<String, dynamic> expected,
) {
  expect(result.samples, hasLength(expected['samples']));
  expect(result.sampleRateHz, expected['sample_rate_hz']);
  final words = (expected['words'] as List).cast<List>();
  expect(result.wordTimestamps, hasLength(words.length));
  for (final (i, word) in result.wordTimestamps.indexed) {
    final [
      String name,
      int startByte,
      int endByte,
      num startSeconds,
      num endSeconds,
    ] = words[i];
    expect(word.word, name);
    expect(text.substring(word.start, word.end), name);
    expect(utf8.encode(text.substring(0, word.start)), hasLength(startByte));
    expect(utf8.encode(text.substring(0, word.end)), hasLength(endByte));
    expect(word.startSeconds, closeTo(startSeconds, _secondsDelta));
    expect(word.endSeconds, closeTo(endSeconds, _secondsDelta));
  }
  final peak = result.samples.fold(0.0, (m, s) => math.max(m, s.abs()));
  expect(peak, closeTo(expected['peak'] as num, _levelDelta));
  final envelope = (expected['envelope'] as List).cast<num>();
  final window = (result.sampleRateHz * 0.1).round();
  expect((result.samples.length + window - 1) ~/ window, envelope.length);
  for (final (i, level) in envelope.indexed) {
    final part = result.samples.sublist(
      i * window,
      math.min((i + 1) * window, result.samples.length),
    );
    final rms = math.sqrt(
      part.fold(0.0, (sum, s) => sum + s * s) / part.length,
    );
    expect(rms, closeTo(level, _levelDelta), reason: 'window $i');
  }
}

/// The RMS of [length] samples from [start].
double _windowRms(Float32List samples, int start, int length) {
  var sum = 0.0;
  for (var i = start; i < start + length; i++) {
    sum += samples[i] * samples[i];
  }
  return math.sqrt(sum / length);
}
