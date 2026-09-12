import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

/// Replays a checked-in portrait through the public VIDEO API without a camera.
/// Build with `dart build cli -t bin/benchmark_delegates.dart` and run from the
/// package root for AOT application timings including input copies and FFI.
Future<void> main(List<String> arguments) async {
  final frames = arguments.isEmpty ? 120 : int.parse(arguments.single);
  if (frames < 20) throw ArgumentError('Measure at least 20 frames.');
  final rgb = File(
    'test/fixtures/face_detection/portrait-301x209.rgb',
  ).readAsBytesSync();
  const width = 1920;
  const height = 1080;
  const stride = width * 4 + 64;
  final bgra = Uint8List(stride * height);
  // Nearest-neighbour enlargement with black side bars, keeping aspect ratio.
  const scaledWidth = height * 301 ~/ 209;
  const left = (width - scaledWidth) ~/ 2;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final destination = y * stride + x * 4;
      bgra[destination + 3] = 255;
      if (x < left || x >= left + scaledWidth) continue;
      final source =
          ((y * 209 ~/ height) * 301 + ((x - left) * 301 ~/ scaledWidth)) * 3;
      bgra[destination] = rgb[source + 2];
      bgra[destination + 1] = rgb[source + 1];
      bgra[destination + 2] = rgb[source];
    }
  }
  for (var round = 0; round < 2; round++) {
    // Reverse order on the second round to expose warm-up/order effects.
    final delegates = round == 0
        ? VisionDelegate.values
        : VisionDelegate.values.reversed;
    for (final delegate in delegates) {
      for (final mesh in [false, true]) {
        final startup = Stopwatch()..start();
        final detector = mesh
            ? null
            : await FaceDetector.create(
                FaceDetectorOptions(
                  modelPath: 'models/blaze_face_short_range.tflite',
                  runningMode: VisionRunningMode.video,
                  delegate: delegate,
                ),
              );
        final landmarker = !mesh
            ? null
            : await FaceLandmarker.create(
                FaceLandmarkerOptions(
                  modelPath: 'models/face_landmarker.task',
                  runningMode: VisionRunningMode.video,
                  delegate: delegate,
                ),
              );
        startup.stop();
        try {
          final timings = <double>[];
          for (var i = 0; i < frames + 20; i++) {
            final timer = Stopwatch()..start();
            final image = VisionImage.fromPixels(
              pixels: bgra,
              width: width,
              height: height,
              bytesPerRow: stride,
              format: VisionPixelFormat.bgra,
            );
            final count = mesh
                ? (await landmarker!.detectForVideo(
                    image,
                    timestampMilliseconds: i * 33,
                  )).faceLandmarks.length
                : (await detector!.detectForVideo(
                    image,
                    timestampMilliseconds: i * 33,
                  )).detections.length;
            timer.stop();
            if (count != 1) throw StateError('Expected one portrait face.');
            if (i >= 20) timings.add(timer.elapsedMicroseconds / 1000);
          }
          timings.sort();
          stdout.writeln(
            jsonEncode({
              'round': round + 1,
              'task': mesh ? 'face_landmarker' : 'face_detector',
              'delegate': delegate.name,
              'input': '1920x1080 padded BGRA portrait replay',
              'frames': frames,
              'warmup_frames': 20,
              'create_ms': startup.elapsedMicroseconds / 1000,
              'mean_ms': timings.reduce((a, b) => a + b) / timings.length,
              'p50_ms': timings[timings.length ~/ 2],
              'p95_ms': timings[(timings.length * 0.95).ceil() - 1],
            }),
          );
        } finally {
          await detector?.dispose();
          await landmarker?.dispose();
        }
      }
    }
  }
}
