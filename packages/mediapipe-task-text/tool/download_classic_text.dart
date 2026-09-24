import 'dart:io';

import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_text/models.dart';

Future<void> main() async {
  for (final model in [
    bertClassifierModel,
    universalSentenceEncoderModel,
    languageDetectorModel,
  ]) {
    final target = File(
      'example/assets/${Uri.parse(model.url).pathSegments.last}',
    );
    await downloadVerified(model, target);
    stdout.writeln('Verified ${target.path}');
  }
}
