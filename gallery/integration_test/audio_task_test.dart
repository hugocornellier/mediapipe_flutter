import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_audio/mediapipe_flutter_audio.dart';

// The Audio Classifier demo's task, from the gallery's bundled YAMNet and
// sample clip, in the same app as the vision and text runtimes: core's shared
// runtime on macOS arm64, Linux x64 and Windows x64, where prepare.py bundles
// it. The mobile and browser plugins have sdk_text_audio_test.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List> asset(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  testWidgets('audio classifier hears speech in the bundled clip', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final task = await AudioClassifier.create(
        AudioClassifierOptions(
          modelBytes: await asset('assets/models/yamnet.tflite'),
          maxResults: 3,
        ),
      );
      try {
        final chunks = await task.classify(
          decodeWav(await asset('assets/samples/speech_16000_hz_mono.wav')),
        );
        expect(chunks, hasLength(5));
        expect(chunks.first.categories.first.name, 'Speech');
        // Google's Python output for this chunk on macOS. YAMNet's scores move
        // in 1/256 steps; the package suite compares each desktop host with
        // Google's library on that host.
        expect(
          chunks.first.categories.first.score,
          closeTo(0.917969, Platform.isMacOS ? 1e-5 : 2 / 256),
        );
      } finally {
        await task.dispose();
      }
    });
  }, skip: !(Platform.isMacOS || Platform.isLinux || Platform.isWindows));
}
