import 'dart:io';

import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_text/mediapipe_text.dart';

Future<void> main() async {
  for (final model in [
    TextModels.bertClassifier,
    TextModels.universalSentenceEncoder,
    TextModels.languageDetector,
  ]) {
    final target = File('models/${Uri.parse(model.url).pathSegments.last}');
    await downloadVerified(model, target);
    stdout.writeln('Verified ${target.path}');
  }
}
