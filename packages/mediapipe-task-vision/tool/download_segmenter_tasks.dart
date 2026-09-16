import 'dart:io';
import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_vision/models.dart';

Future<void> main() async {
  for (final (name, url, digest) in [
    ('deeplab_v3.tflite', deepLabV3Url, deepLabV3Sha256),
    ('magic_touch.tflite', magicTouchUrl, magicTouchSha256),
  ]) {
    await downloadVerified((url: url, sha256: digest), File('models/$name'));
    stdout.writeln('Verified model: models/$name');
  }
}
