import 'dart:io';

import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_vision/models.dart';

Future<void> main(List<String> arguments) async {
  final destination = arguments.isEmpty
      ? 'models/blaze_face_short_range.tflite'
      : arguments.single;
  await downloadVerified((
    url: blazeFaceShortRangeUrl,
    sha256: blazeFaceShortRangeSha256,
  ), File(destination));
  stdout.writeln('Verified model: $destination');
}
