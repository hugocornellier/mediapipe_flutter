import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_audio/mediapipe_flutter_audio.dart';

// The Audio Classifier demo's task, from the gallery's bundled YAMNet and
// sample clip, in the same app as the vision and text runtimes. macOS arm64
// only, where prepare.py bundles it.
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
        // Google's Python 1.0.1 output for this chunk.
        expect(chunks.first.categories.first.score, closeTo(0.917969, 1e-5));
      } finally {
        await task.dispose();
      }
    });
  }, skip: !Platform.isMacOS);
}
