import 'dart:io';

import 'package:mediapipe_audio/mediapipe_audio.dart';

/// Classifies a 16-bit PCM WAV clip with Google's pinned YAMNet model, which
/// is downloaded and verified on first use.
Future<void> main(List<String> arguments) async {
  final classifier = await AudioClassifier.create(
    AudioClassifierOptions(model: AudioModels.yamnet, maxResults: 3),
  );
  try {
    final clip = decodeWav(await File(arguments.single).readAsBytes());
    for (final chunk in await classifier.classify(clip)) {
      final labels = chunk.categories
          .map((c) => '${c.name} ${c.score.toStringAsFixed(2)}')
          .join(', ');
      print('${chunk.timestampMs} ms: $labels');
    }
  } finally {
    await classifier.dispose();
  }
}
