import 'dart:io';

import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

Future<void> main(List<String> arguments) async {
  final destination = arguments.isEmpty
      ? 'models/blaze_face_short_range.tflite'
      : arguments.single;
  await downloadVerified(VisionModels.faceDetector, File(destination));
  stdout.writeln('Verified model: $destination');
}
