import 'dart:io';

import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_retrieval/mediapipe_retrieval.dart';

/// Downloads and verifies the two EmbeddingGemma 2 models the native tests
/// run into `models/`: the text and vision model, and the full one, the only
/// one that embeds audio.
Future<void> main() async {
  for (final model in [
    RetrievalModels.embeddingGemma2TextVision,
    RetrievalModels.embeddingGemma2,
  ]) {
    final target = File('models/${Uri.parse(model.url).pathSegments.last}');
    await downloadVerified(model, target);
    stdout.writeln('Verified ${target.path}');
  }
}
