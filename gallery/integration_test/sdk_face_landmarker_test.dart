import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_vision/face_landmarker_backend.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_gallery/live/live_camera_controller.dart';
import 'package:mediapipe_gallery/live/live_tasks.dart';
import 'package:mediapipe_gallery/live/live_camera_view.dart';
import 'package:mediapipe_gallery/main.dart';

/// `skip` on emulators: SwiftShader GL accepts a GPU task, then TFLite's GL
/// delegate fails on the first frame (see test_android_sdk_tasks.sh). GPU is
/// then a phone check, as for the other SDK suites.
const _gpu = String.fromEnvironment('SDK_GPU', defaultValue: 'optional');
const _delegates = [VisionDelegate.cpu, if (_gpu != 'skip') VisionDelegate.gpu];
const _switches = [
  VisionDelegate.cpu,
  if (_gpu != 'skip') ...[VisionDelegate.gpu, VisionDelegate.cpu],
];

// Face Landmarker through Google's official mobile SDKs: iOS through the
// package's Objective-C adapter, Android through
// mediapipe_flutter_vision_android. Runs on the iOS simulator and Android
// emulator in CI (CPU), and on phones (CPU and GPU).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'official SDK CPU and GPU: face pixels, padding, optional outputs',
    (tester) async {
      await tester.runAsync(() async {
        expect(Platform.isAndroid || Platform.isIOS, isTrue);
        if (Platform.isAndroid) {
          expect(
            faceLandmarkerBackendFactory,
            isNotNull,
            reason: 'Android SDK plugin must register automatically',
          );
        }
        final assets = await GalleryAssets.unpack();
        final model = await _model();
        final frame = await _portrait();
        final references = <FaceLandmarkerResult>[];
        for (final delegate in _delegates) {
          final task = await FaceLandmarker.create(
            FaceLandmarkerOptions(
              modelBytes: model,
              delegate: delegate,
              outputFaceBlendshapes: true,
              outputFacialTransformationMatrixes: true,
            ),
          );
          try {
            final reference = await task.detectImage(frame.image);
            _face(reference, optional: true);
            references.add(reference);
            final copied = reference.faceLandmarks.single.first.x;
            for (final format in VisionPixelFormat.values) {
              final channels = format.channels;
              final stride = frame.width * channels + 16;
              final pixels = Uint8List(stride * frame.height);
              for (var y = 0; y < frame.height; y++) {
                for (var x = 0; x < frame.width; x++) {
                  final src = (y * frame.width + x) * 4;
                  final dst = y * stride + x * channels;
                  pixels[dst] = frame
                      .pixels[src + (format == VisionPixelFormat.bgra ? 2 : 0)];
                  pixels[dst + 1] = frame.pixels[src + 1];
                  pixels[dst + 2] = frame
                      .pixels[src + (format == VisionPixelFormat.bgra ? 0 : 2)];
                  if (channels == 4) pixels[dst + 3] = 255;
                }
              }
              final padded = await task.detectImage(
                VisionImage.fromPixels(
                  pixels: pixels,
                  width: frame.width,
                  height: frame.height,
                  format: format,
                  bytesPerRow: stride,
                ),
              );
              expect(
                _delta(reference, padded),
                lessThan(1e-5),
                reason: format.name,
              );
            }
            _face(
              await task.detectImage(
                VisionImage.fromFile(assets.path('portrait.jpg')),
              ),
              optional: true,
            );
            final blank = await task.detectImage(_blank());
            expect(blank.faceLandmarks, isEmpty);
            expect(blank.faceBlendshapes, isEmpty);
            expect(blank.facialTransformationMatrixes, isEmpty);
            expect(reference.faceLandmarks.single.first.x, copied);
            _report('image', {
              'delegate': delegate.name,
              'landmarks': 478,
              'blendshapes': reference.faceBlendshapes.single.length,
              'matrix': reference.facialTransformationMatrixes.single.values,
            });
          } finally {
            await task.dispose();
          }
          await task.dispose();
          await expectLater(task.detectImage(frame.image), throwsStateError);
        }
        if (references.length == 2) {
          final delta = _delta(references[0], references[1]);
          expect(
            delta,
            lessThan(0.03),
            reason: 'CPU/GPU must detect the same face geometry',
          );
          _report('cpu_gpu', {'max_landmark_delta': delta});
        }
        await expectLater(
          FaceLandmarker.create(
            FaceLandmarkerOptions(
              modelBytes: Uint8List.fromList([1, 2, 3]),
              delegate: _delegates.last,
            ),
          ),
          throwsA(isA<FaceLandmarkerException>()),
        );
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets('official SDK VIDEO: tracking, rotation, queued frames, cleanup', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final assets = await GalleryAssets.unpack();
      final frame = await _portrait();
      for (final delegate in _switches) {
        final task = await FaceLandmarker.create(
          FaceLandmarkerOptions(
            modelPath: assets.path('face_landmarker.task'),
            delegate: delegate,
            runningMode: VisionRunningMode.video,
          ),
        );
        try {
          await expectLater(task.detectImage(frame.image), throwsStateError);
          await expectLater(
            task.detectForVideo(frame.image, timestampMilliseconds: -1),
            throwsArgumentError,
          );
          await expectLater(
            task.detectForVideo(
              frame.image,
              timestampMilliseconds: 0,
              rotationDegrees: 45,
            ),
            throwsArgumentError,
          );
          final results = await Future.wait([
            task.detectForVideo(frame.image, timestampMilliseconds: 0),
            task.detectForVideo(frame.image, timestampMilliseconds: 33),
          ]);
          _face(results.first);
          expect(results.map((r) => r.timestampMilliseconds), [0, 33]);
          await expectLater(
            task.detectForVideo(frame.image, timestampMilliseconds: 33),
            throwsArgumentError,
          );
          for (var i = 2; i < 20; i++) {
            final result = await task.detectForVideo(
              frame.image,
              timestampMilliseconds: i * 33,
            );
            _face(result);
            expect(result.timestampMilliseconds, i * 33);
          }
          final empty = await task.detectForVideo(
            _blank(),
            timestampMilliseconds: 660,
          );
          expect(empty.faceLandmarks, isEmpty);
          _face(
            await task.detectForVideo(frame.image, timestampMilliseconds: 693),
          );
          _report('video', {
            'delegate': delegate.name,
            'face_frames': 21,
            'blank_frames': 1,
            'queued_frames': 2,
          });
        } finally {
          await task.dispose();
        }
      }
      // A camera can deliver a rotated sensor buffer. Rotate its pixels back
      // before asking MediaPipe for the turn; geometry must remain in input space.
      for (final delegate in _delegates) {
        final task = await FaceLandmarker.create(
          FaceLandmarkerOptions(modelBytes: await _model(), delegate: delegate),
        );
        try {
          for (final turn in [0, 90, 180, 270]) {
            final rotated = _rotate(frame, (360 - turn) % 360);
            _face(await task.detectImage(rotated, rotationDegrees: turn));
          }
        } finally {
          await task.dispose();
        }
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('camera: CPU to GPU to CPU, front and back', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Testing Android Face Landmarker')),
      ),
    );
    await tester.runAsync(() async {
      final controller = LiveCameraController<FaceLandmarkerResult>(
        FaceLandmarkerLiveTask(),
      );
      try {
        final cameras = await controller.findCameras();
        // The iOS simulator has no camera; Android emulators emulate one.
        if (cameras.isEmpty && Platform.isIOS) {
          _report('camera', {'cameras': 0});
          return;
        }
        expect(cameras, isNotEmpty);
        for (final delegate in _switches) {
          await controller.start(
            delegate: delegate,
            modelAsset: 'assets/models/face_landmarker.task',
          );
          await _frames(controller);
          _cameraReport(controller);
        }
        if (controller.canSwitchCamera) {
          await controller.switchCamera();
          await _frames(controller);
          _cameraReport(controller);
          await controller.start(delegate: _delegates.last);
          await _frames(controller);
          _cameraReport(controller);
        }
      } finally {
        await controller.close();
        controller.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('gallery opens Live Face Landmarker and switches CPU/GPU', (
    tester,
  ) async {
    await tester.pumpWidget(const GalleryApp());
    for (
      var i = 0;
      i < 100 && find.text('Live Face Landmarker').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.text('Live Face Landmarker'), findsOneWidget);
    await tester.tap(find.text('Live Face Landmarker'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LiveCameraView), findsOneWidget);
    final controller = tester
        .widget<LiveCameraView>(find.byType(LiveCameraView))
        .controller;
    Future<void> waitFor(VisionDelegate delegate) async {
      final deadline = DateTime.now().add(const Duration(seconds: 35));
      while ((controller.delegate != delegate ||
              controller.changing ||
              controller.processedFrames < 20) &&
          controller.error == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(controller.error, isNull);
      expect(controller.delegate, delegate);
      expect(controller.processedFrames, greaterThanOrEqualTo(20));
      expect(controller.result, isA<FaceLandmarkerResult>());
    }

    // A simulator may have no camera; the demo must then say so.
    final deadline = DateTime.now().add(const Duration(seconds: 35));
    while (controller.cameras.isEmpty &&
        controller.error == null &&
        controller.processedFrames == 0 &&
        DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    if (controller.cameras.isEmpty && Platform.isIOS) {
      expect(find.textContaining('No camera found'), findsOneWidget);
      _report('gallery', {'cameras': 0});
      await tester.runAsync(controller.close);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      return;
    }
    await tester.runAsync(() => waitFor(VisionDelegate.cpu));
    await tester.pump();
    expect(find.text('GPU'), findsOneWidget);
    for (final delegate in _switches.skip(1)) {
      await tester.tap(
        find.text(delegate == VisionDelegate.gpu ? 'GPU' : 'CPU'),
      );
      await tester.pump();
      await tester.runAsync(() => waitFor(delegate));
      await tester.pump();
    }
    _report('gallery', {
      'delegates': [for (final delegate in _switches) delegate.name],
      'frames_per_stage': 20,
    });
    await controller.close();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<Uint8List> _model() async {
  final bytes = await rootBundle.load('assets/models/face_landmarker.task');
  return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}

typedef _Frame = ({int width, int height, Uint8List pixels, VisionImage image});
Future<_Frame> _portrait() async {
  final bytes = await rootBundle.load('assets/samples/portrait.jpg');
  final codec = await ui.instantiateImageCodec(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
  final image = (await codec.getNextFrame()).image;
  try {
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final pixels = rgba.buffer.asUint8List(
      rgba.offsetInBytes,
      rgba.lengthInBytes,
    );
    return (
      width: image.width,
      height: image.height,
      pixels: pixels,
      image: VisionImage.fromPixels(
        pixels: pixels,
        width: image.width,
        height: image.height,
        format: VisionPixelFormat.rgba,
      ),
    );
  } finally {
    image.dispose();
    codec.dispose();
  }
}

VisionImage _blank() => VisionImage.fromPixels(
  pixels: Uint8List(64 * 64 * 3),
  width: 64,
  height: 64,
  format: VisionPixelFormat.rgb,
);

VisionImage _rotate(_Frame frame, int turn) {
  final width = turn % 180 == 0 ? frame.width : frame.height;
  final height = turn % 180 == 0 ? frame.height : frame.width;
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final (dx, dy) = switch (turn) {
        90 => (frame.height - 1 - y, x),
        180 => (frame.width - 1 - x, frame.height - 1 - y),
        270 => (y, frame.width - 1 - x),
        _ => (x, y),
      };
      pixels.setRange(
        (dy * width + dx) * 4,
        (dy * width + dx) * 4 + 4,
        frame.pixels,
        (y * frame.width + x) * 4,
      );
    }
  }
  return VisionImage.fromPixels(
    pixels: pixels,
    width: width,
    height: height,
    format: VisionPixelFormat.rgba,
  );
}

void _face(FaceLandmarkerResult result, {bool optional = false}) {
  expect(result.faceLandmarks, hasLength(1));
  expect(result.faceLandmarks.single, hasLength(478));
  for (final point in result.faceLandmarks.single) {
    expect(point.x.isFinite && point.y.isFinite && point.z.isFinite, isTrue);
  }
  if (optional) {
    expect(result.faceBlendshapes.single, hasLength(52));
    final matrix = result.facialTransformationMatrixes.single;
    expect(matrix.values, hasLength(16));
    for (final value in matrix.values) {
      expect(value.isFinite, isTrue);
    }
    // Column-major contract: the affine bottom row is [0,0,0,1].
    for (var c = 0; c < 4; c++) {
      expect(matrix.at(3, c), closeTo(c == 3 ? 1 : 0, 1e-5));
    }
  }
}

double _delta(FaceLandmarkerResult a, FaceLandmarkerResult b) {
  _face(a);
  _face(b);
  var maximum = 0.0;
  for (var i = 0; i < 478; i++) {
    final p = a.faceLandmarks.single[i], q = b.faceLandmarks.single[i];
    maximum = math.max(
      maximum,
      math.max(
        (p.x - q.x).abs(),
        math.max((p.y - q.y).abs(), (p.z - q.z).abs()),
      ),
    );
  }
  return maximum;
}

Future<void> _frames(
  LiveCameraController<FaceLandmarkerResult> controller,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 35));
  while (controller.processedFrames < 20 &&
      controller.error == null &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(controller.error, isNull);
  expect(controller.processedFrames, greaterThanOrEqualTo(20));
  expect(controller.result!.imageWidth, greaterThan(0));
  expect(controller.result!.imageHeight, greaterThan(0));
  expect(controller.result!.timestampMilliseconds, isNotNull);
}

void _cameraReport(LiveCameraController<FaceLandmarkerResult> c) =>
    _report('camera', {
      'delegate': c.delegate.name,
      'lens': c.description!.lensDirection.name,
      'rotation': c.frameRotationDegrees,
      'frames': c.processedFrames,
      'width': c.result!.imageWidth,
      'height': c.result!.imageHeight,
      'faces': c.result!.faceLandmarks.length,
      'mean_inference_ms': c.averageInferenceMilliseconds,
    });

void _report(String event, Map<String, Object?> data) {
  // Preserved in Test Lab logcat; timings are diagnostic, not a benchmark.
  // ignore: avoid_print
  print('SDK_FACE_LANDMARKER ${jsonEncode({'event': event, ...data})}');
}
