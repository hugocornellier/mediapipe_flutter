import 'dart:io';

import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_retrieval/mediapipe_retrieval.dart';

/// Downloads and verifies Google's EmbeddingGemma 2 text and vision model for the native
/// tests.
Future<void> main(List<String> args) async {
  final target = File(
    args.isEmpty
        ? 'models/embeddinggemma-2-text-vision-440m.litertlm'
        : args.single,
  );
  await downloadVerified(RetrievalModels.embeddingGemma2TextVision, target);
  stdout.writeln('Verified ${target.path}');
}
