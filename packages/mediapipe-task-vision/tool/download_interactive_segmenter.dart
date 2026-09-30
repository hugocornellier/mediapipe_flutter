import 'dart:io';

import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';

Future<void> main(List<String> arguments) async {
  final destination = arguments.isEmpty
      ? 'models/interactive_segmentation.task'
      : arguments.single;
  await downloadVerified(VisionModels.interactiveSegmenter, File(destination));
  stdout.writeln('Verified model: $destination');
}
