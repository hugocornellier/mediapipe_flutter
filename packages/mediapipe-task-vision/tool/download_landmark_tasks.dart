import 'dart:io';
import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

Future<void> main() async {
  for (final (name, model) in [
    ('hand_landmarker.task', VisionModels.handLandmarker),
    ('gesture_recognizer.task', VisionModels.gestureRecognizer),
    ('pose_landmarker_lite.task', VisionModels.poseLandmarker),
    ('holistic_landmarker.task', VisionModels.holisticLandmarker),
  ]) {
    await downloadVerified(model, File('models/$name'));
    stdout.writeln('Verified model: models/$name');
  }
}
