// Run as a release app on an iPhone after prepare.py --target ios/arm64.
// Exercises the Dart worker/FFI adapter, not just the native Objective-C SDK.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_gallery/main.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Checking Google iOS SDK: CPU, GPU, pixels and rotations…',
          ),
        ),
      ),
    ),
  );
  final report = <String, Object?>{'event': 'failed', 'sdk': '1.0.1'};
  try {
    require(Platform.isIOS, 'Run this on iOS.');
    final assets = await GalleryAssets.unpack();
    require(
      assets.manifest['official_ios_sdk'] == '1.0.1',
      'Official SDK not selected.',
    );
    final data = await rootBundle.load('assets/models/face_landmarker.task');
    final model = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final photo = await rootBundle.load('assets/samples/portrait.jpg');
    final codec = await ui.instantiateImageCodec(
      photo.buffer.asUint8List(photo.offsetInBytes, photo.lengthInBytes),
    );
    final decoded = (await codec.getNextFrame()).image;
    final pixels = (await decoded.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final rgba = VisionImage.fromPixels(
      pixels: pixels.buffer.asUint8List(
        pixels.offsetInBytes,
        pixels.lengthInBytes,
      ),
      width: decoded.width,
      height: decoded.height,
      format: VisionPixelFormat.rgba,
    );
    decoded.dispose();
    codec.dispose();
    final outcomes = <Map<String, Object?>>[];
    final baselineByDelegate = <VisionDelegate, FaceLandmarkerResult>{};
    // Landmarker is the system alias: create it before the bundled detector
    // asset is ever called, proving the alias loads the same library itself.
    for (final delegate in [VisionDelegate.cpu, VisionDelegate.gpu]) {
      final landmarker = await FaceLandmarker.create(
        FaceLandmarkerOptions(
          modelBytes: model,
          delegate: delegate,
          outputFaceBlendshapes: true,
          outputFacialTransformationMatrixes: true,
        ),
      );
      try {
        final baseline = await landmarker.detectImage(rgba);
        require(
          baseline.faceLandmarks.length == 1,
          '$delegate RGBA found no face.',
        );
        require(
          baseline.faceLandmarks.single.length == 478,
          '$delegate incomplete mesh.',
        );
        require(
          baseline.faceBlendshapes.single.length == 52,
          '$delegate missing blendshapes.',
        );
        require(
          baseline.facialTransformationMatrixes.single.values.length == 16,
          '$delegate missing transform.',
        );
        baselineByDelegate[delegate] = baseline;
        final file = await landmarker.detectImage(
          VisionImage.fromFile(assets.path('portrait.jpg')),
        );
        require(
          file.faceLandmarks.length == 1,
          '$delegate file image found no face.',
        );
        // UIKit and Flutter use different JPEG decoders/color conversion.
        // File loading must detect the face; equivalence checks below use
        // identical decoded pixels in all three channel orders instead.
        final filePixelDelta = _difference(baseline, file);
        for (final format in VisionPixelFormat.values) {
          final padded = _convert(rgba, format);
          final result = await landmarker.detectImage(padded);
          require(
            result.faceLandmarks.length == 1,
            '$delegate $format found no face.',
          );
          require(
            _difference(baseline, result) < 0.001,
            '$delegate padded $format changed coordinates.',
          );
        }
        final rotationDeltas = <String, double>{};
        for (final angle in [90, 180, 270]) {
          final turned = _rotate(rgba, (360 - angle) % 360);
          final result = await landmarker.detectImage(
            turned,
            rotationDegrees: angle,
          );
          require(
            result.faceLandmarks.length == 1,
            '$delegate rotation $angle found no face.',
          );
          double maximum = 0;
          for (var i = 0; i < 478; i++) {
            final actual = result.faceLandmarks.single[i];
            final expected = baseline.faceLandmarks.single[i];
            final (x, y) = switch (angle) {
              90 => (1 - actual.y, actual.x),
              180 => (1 - actual.x, 1 - actual.y),
              _ => (actual.y, 1 - actual.x),
            };
            final delta = [
              (x - expected.x).abs(),
              (y - expected.y).abs(),
            ].reduce((a, b) => a > b ? a : b);
            if (delta > maximum) maximum = delta;
          }
          // Physically rotating a raster changes sampling at pixel centres;
          // this is a coordinate-space check, not a bit-identical oracle.
          // Check alignment within 1% CPU / 3% GPU; record the actual deltas.
          require(
            maximum < (delegate == VisionDelegate.gpu ? 0.03 : 0.01),
            '$delegate rotation $angle remaps incorrectly: $maximum.',
          );
          rotationDeltas['$angle'] = maximum;
        }
        final blank = await landmarker.detectImage(
          VisionImage.fromPixels(
            pixels: Uint8List(128 * 128 * 4),
            width: 128,
            height: 128,
            format: VisionPixelFormat.bgra,
          ),
        );
        require(
          blank.faceLandmarks.isEmpty &&
              blank.faceBlendshapes.isEmpty &&
              blank.facialTransformationMatrixes.isEmpty,
          '$delegate blank frame returned a face.',
        );
        // Grow after the 128px blank frame, reuse the buffer with face pixels,
        // then shrink and grow again. A pool must not return stale contents.
        for (var cycle = 0; cycle < 2; cycle++) {
          final restored = await landmarker.detectImage(
            _convert(rgba, VisionPixelFormat.bgra),
          );
          require(
            _difference(baseline, restored) < 0.001,
            '$delegate changed face pixels after resizing storage.',
          );
          final empty = await landmarker.detectImage(
            VisionImage.fromPixels(
              pixels: Uint8List(128 * 128 * 4),
              width: 128,
              height: 128,
              format: VisionPixelFormat.bgra,
            ),
          );
          require(
            empty.faceLandmarks.isEmpty,
            '$delegate reused stale face pixels after shrinking storage.',
          );
        }
        outcomes.add({
          'delegate': delegate.name,
          'image': 'passed',
          'padded_rgb_rgba_bgra': 'passed',
          'file_pixel_max_delta': filePixelDelta,
          'rotation_max_deltas': rotationDeltas,
          'blank': 'passed',
          'bgra_resize_and_reuse': 'passed',
        });
      } finally {
        await landmarker.dispose();
        await landmarker.dispose();
      }
      // Both assets in one process, and both in worker isolates: a duplicated
      // library would abort during the second task's graph registrations.
      final detector = await FaceDetector.create(
        FaceDetectorOptions(
          modelPath: assets.path('blaze_face_short_range.tflite'),
          delegate: delegate,
        ),
      );
      try {
        final result = await detector.detectImage(
          _convert(rgba, VisionPixelFormat.bgra),
        );
        require(
          result.detections.length == 1,
          '$delegate face detector failed.',
        );
        require(
          result.detections.single.keypoints.length == 6,
          '$delegate missing detector keypoints.',
        );
      } finally {
        await detector.dispose();
      }
      final video = await FaceLandmarker.create(
        FaceLandmarkerOptions(
          modelBytes: model,
          delegate: delegate,
          runningMode: VisionRunningMode.video,
        ),
      );
      try {
        for (var i = 0; i < 8; i++) {
          final result = await video.detectForVideo(
            _convert(rgba, VisionPixelFormat.bgra),
            timestampMilliseconds: i * 33,
          );
          require(
            result.faceLandmarks.length == 1 &&
                result.faceLandmarks.single.length == 478,
            '$delegate VIDEO frame $i failed.',
          );
          require(
            result.timestampMilliseconds == i * 33,
            'VIDEO timestamp lost.',
          );
        }
        var rejected = false;
        try {
          await video.detectForVideo(rgba, timestampMilliseconds: 0);
        } on ArgumentError {
          rejected = true;
        }
        require(rejected, 'Nonmonotonic timestamp was accepted.');
      } finally {
        await video.dispose();
      }
      // Creation failures must clean up model bytes and leave later creation usable.
      var rejected = false;
      try {
        await FaceLandmarker.create(
          FaceLandmarkerOptions(
            modelBytes: Uint8List.fromList([1, 2, 3]),
            delegate: delegate,
          ),
        );
      } on FaceLandmarkerException {
        rejected = true;
      }
      require(rejected, '$delegate accepted a corrupt model.');
      final recovery = await FaceLandmarker.create(
        FaceLandmarkerOptions(modelBytes: model, delegate: delegate),
      );
      await recovery.dispose();
      outcomes.last['video_frames'] = 8;
      outcomes.last['detector_keypoints'] = 6;
      outcomes.last['error_recovery'] = 'passed';
    }
    final difference = _difference(
      baselineByDelegate[VisionDelegate.cpu]!,
      baselineByDelegate[VisionDelegate.gpu]!,
    );
    // CPU/GPU parity depends on the SDK and device's precision. This is a
    // functionality smoke test; report the difference without inventing an
    // iOS accuracy tolerance from the macOS wheel's reference bounds.
    report.addAll({
      'event': 'complete',
      'delegates': outcomes,
      'cpu_gpu_max_landmark_delta': difference,
    });
  } catch (error, stack) {
    report.addAll({'error': '$error', 'stack': '$stack'});
  }
  await File(
    '${Directory.systemTemp.path}/gallery-ios-sdk-smoke.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  stdout.writeln('GALLERY_IOS_SDK_SMOKE ${jsonEncode(report)}');
  exit(report['event'] == 'complete' ? 0 : 1);
}

double _difference(FaceLandmarkerResult a, FaceLandmarkerResult b) {
  require(
    a.faceLandmarks.length == b.faceLandmarks.length,
    'Face counts differ.',
  );
  double maximum = 0;
  for (var i = 0; i < a.faceLandmarks.single.length; i++) {
    final left = a.faceLandmarks.single[i];
    final right = b.faceLandmarks.single[i];
    for (final difference in [
      (left.x - right.x).abs(),
      (left.y - right.y).abs(),
      (left.z - right.z).abs(),
    ]) {
      if (difference > maximum) maximum = difference;
    }
  }
  return maximum;
}

VisionImage _convert(VisionImage rgba, VisionPixelFormat format) {
  final width = rgba.width!, height = rgba.height!;
  final stride = width * format.channels + 16;
  final output = Uint8List(stride * height)
    ..fillRange(0, stride * height, 0xa5);
  final source = rgba.pixels!;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final from = (y * width + x) * 4, to = y * stride + x * format.channels;
      final bgra = format == VisionPixelFormat.bgra;
      output[to] = source[from + (bgra ? 2 : 0)];
      output[to + 1] = source[from + 1];
      output[to + 2] = source[from + (bgra ? 0 : 2)];
      if (format.channels == 4) output[to + 3] = source[from + 3];
    }
  }
  return VisionImage.fromPixels(
    pixels: output,
    width: width,
    height: height,
    bytesPerRow: stride,
    format: format,
  );
}

VisionImage _rotate(VisionImage rgba, int angle) {
  final width = rgba.width!, height = rgba.height!;
  final targetWidth = angle == 180 ? width : height;
  final targetHeight = angle == 180 ? height : width;
  final output = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final (tx, ty) = switch (angle) {
        90 => (height - 1 - y, x),
        180 => (width - 1 - x, height - 1 - y),
        _ => (y, width - 1 - x),
      };
      final from = (y * width + x) * 4, to = (ty * targetWidth + tx) * 4;
      output.setRange(to, to + 4, rgba.pixels!, from);
    }
  }
  return VisionImage.fromPixels(
    pixels: output,
    width: targetWidth,
    height: targetHeight,
    format: VisionPixelFormat.rgba,
  );
}
