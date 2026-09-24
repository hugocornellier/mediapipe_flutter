import 'dart:io';

import 'package:mediapipe_flutter_audio/models.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';

Future<void> main() async {
  await downloadVerified((
    url: yamnetUrl,
    sha256: yamnetSha256,
  ), File('models/yamnet.tflite'));
  stdout.writeln('Verified model: models/yamnet.tflite');
}
