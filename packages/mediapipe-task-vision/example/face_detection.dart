import 'dart:io';

import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run example/face_detection.dart model.tflite image.jpg',
    );
    exitCode = 64;
    return;
  }
  final detector = await FaceDetector.create(
    FaceDetectorOptions(modelPath: arguments[0]),
  );
  try {
    final result = await detector.detectImage(
      VisionImage.fromFile(arguments[1]),
    );
    stdout.writeln(
      '${result.detections.length} face(s) in '
      '${result.imageWidth} × ${result.imageHeight} image',
    );
    for (final face in result.detections) {
      final box = face.boundingBox;
      stdout.writeln(
        'confidence=${face.categories.first.score.toStringAsFixed(6)} '
        'box=(${box.left}, ${box.top}, ${box.width}, ${box.height}) '
        'keypoints=${face.keypoints.length}',
      );
    }
  } finally {
    await detector.dispose();
  }
}
