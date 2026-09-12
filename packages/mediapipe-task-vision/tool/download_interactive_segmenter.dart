import 'dart:io';

import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_vision/models.dart';

Future<void> main(List<String> arguments) async {
  final destination = arguments.isEmpty
      ? 'models/interactive_segmentation.task'
      : arguments.single;
  await downloadVerified((
    url: interactiveSegmenterModelUrl,
    sha256: interactiveSegmenterModelSha256,
  ), File(destination));
  stdout.writeln('Verified model: $destination');
}
