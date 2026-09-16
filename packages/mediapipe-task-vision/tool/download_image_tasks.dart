import 'dart:io';

import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_vision/models.dart';

Future<void> main() async {
  for (final (name, url, digest) in [
    (
      'efficientnet_lite0.tflite',
      efficientNetLite0Url,
      efficientNetLite0Sha256,
    ),
    ('mobilenet_v3_small.tflite', mobileNetV3SmallUrl, mobileNetV3SmallSha256),
  ]) {
    await downloadVerified((url: url, sha256: digest), File('models/$name'));
    stdout.writeln('Verified model: models/$name');
  }
}
