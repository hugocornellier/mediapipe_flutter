import 'dart:io';

import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_vision/models.dart';

Future<void> main(List<String> arguments) async {
  final destination = arguments.isEmpty
      ? 'models/face_landmarker.task'
      : arguments.single;
  await downloadVerified((
    url: faceLandmarkerUrl,
    sha256: faceLandmarkerSha256,
  ), File(destination));
  stdout.writeln('Verified model: $destination');
}
