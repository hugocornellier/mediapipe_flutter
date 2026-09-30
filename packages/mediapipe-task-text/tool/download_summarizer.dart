import 'dart:io';

import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_text/mediapipe_text.dart';

Future<void> main(List<String> args) async {
  final target = File(
    args.isEmpty
        ? 'models/summarization_quant_200m_2modes.litertlm'
        : args.single,
  );
  await downloadVerified(TextModels.summarizer, target);
  stdout.writeln('Verified ${target.path}');
}
