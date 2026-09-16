import 'dart:io';

import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_vision/models.dart';

Future<void> main(List<String> arguments) async {
  final destination = arguments.isEmpty
      ? 'models/efficientdet_lite0.tflite'
      : arguments.single;
  await downloadVerified((
    url: efficientDetLite0Url,
    sha256: efficientDetLite0Sha256,
  ), File(destination));
  stdout.writeln('Verified model: $destination');
}
