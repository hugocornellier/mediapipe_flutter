import 'dart:io';

import 'package:mediapipe_audio/mediapipe_audio.dart';
import 'package:mediapipe_audio/src/io/native_speech.dart';
import 'package:test/test.dart';

import 'support/metal_memory.dart';

// A diagnostic, not a check: one task on one delegate per process, as a
// delegate may abort it, printing what the task did. PROBE is
// "<tts|asr>-<cpu|gpu>".
const _text = 'The quick brown fox jumps over the lazy dog.';

void main() {
  final probe = Platform.environment['PROBE'] ?? 'tts-gpu';
  final delegate = probe.endsWith('gpu') ? Delegate.gpu : Delegate.cpu;

  test(probe, timeout: const Timeout(Duration(minutes: 15)), () async {
    final metalBefore = Platform.isMacOS ? metalAllocatedBytes() : 0;
    final watch = Stopwatch()..start();
    final List<int> runs = [];
    try {
      if (probe.startsWith('tts')) {
        final task = await openNativeTextToSpeech(
          TextToSpeechOptions(
            modelPath: 'models/phonon_int8.litertlm',
            delegate: delegate,
          ),
        );
        print('PROBE $probe open ms=${watch.elapsedMilliseconds}');
        for (var i = 0; i < 3; i++) {
          watch.reset();
          final result = await task.synthesize(_text, null, null);
          runs.add(watch.elapsedMilliseconds);
          print('PROBE $probe samples=${result.samples.length}');
        }
        if (Platform.isMacOS) _printMetal(probe, metalBefore);
        await task.dispose();
      } else {
        final audio = decodeWav(
          File('test/fixtures/speech_16000_hz_mono.wav').readAsBytesSync(),
        );
        final task = await openNativeAudioTranscriber(
          AudioTranscriberOptions(
            modelPath: 'models/parakeet_tdt_0.6b_v3_5s_i8_stateful.litertlm',
            delegate: delegate,
          ),
        );
        print('PROBE $probe open ms=${watch.elapsedMilliseconds}');
        for (var i = 0; i < 3; i++) {
          watch.reset();
          final result = await task.transcribe(audio.samples, true);
          runs.add(watch.elapsedMilliseconds);
          print('PROBE $probe text=${result.text}');
        }
        if (Platform.isMacOS) _printMetal(probe, metalBefore);
        await task.dispose();
      }
      print('PROBE $probe OK runs ms=$runs');
    } catch (error) {
      print('PROBE $probe ERROR $error');
    }
  });
}

void _printMetal(String probe, int before) =>
    print('PROBE $probe metal bytes added=${metalAllocatedBytes() - before}');
