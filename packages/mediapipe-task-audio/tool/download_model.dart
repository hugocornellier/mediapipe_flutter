import 'dart:io';

import 'package:mediapipe_audio/mediapipe_audio.dart';
import 'package:mediapipe_core/native_assets.dart';

Future<void> main() async {
  await downloadVerified(AudioModels.yamnet, File('models/yamnet.tflite'));
  stdout.writeln('Verified model: models/yamnet.tflite');
}
