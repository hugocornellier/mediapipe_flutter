import 'dart:io';

import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_text/mediapipe_text.dart';

Future<void> main(List<String> args) async {
  final target = File(
    args.isEmpty ? 'models/embedding_gemma.task' : args.single,
  );
  await downloadVerified(TextModels.embeddingGemma, target);
  stdout.writeln('Verified ${target.path}');
}
