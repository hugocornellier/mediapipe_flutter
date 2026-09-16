import 'dart:io';
import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_vision/models.dart';

Future<void> main() async {
  for (final (name, url, digest) in [
    ('hand_landmarker.task', handLandmarkerUrl, handLandmarkerSha256),
    ('gesture_recognizer.task', gestureRecognizerUrl, gestureRecognizerSha256),
    (
      'pose_landmarker_lite.task',
      poseLandmarkerLiteUrl,
      poseLandmarkerLiteSha256,
    ),
    (
      'holistic_landmarker.task',
      holisticLandmarkerUrl,
      holisticLandmarkerSha256,
    ),
  ]) {
    await downloadVerified((url: url, sha256: digest), File('models/$name'));
    stdout.writeln('Verified model: models/$name');
  }
}
