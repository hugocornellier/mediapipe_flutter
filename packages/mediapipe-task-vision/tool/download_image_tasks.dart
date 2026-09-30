import 'dart:io';

import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

Future<void> main() async {
  for (final (name, model) in [
    ('efficientnet_lite0.tflite', VisionModels.imageClassifier),
    ('mobilenet_v3_small.tflite', VisionModels.imageEmbedder),
  ]) {
    await downloadVerified(model, File('models/$name'));
    stdout.writeln('Verified model: models/$name');
  }
}
