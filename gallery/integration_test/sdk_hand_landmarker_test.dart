import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_flutter_vision/vision_task_backend.dart'
    show handLandmarkerBackendFactory;
import 'package:mediapipe_gallery/live/live_camera_view.dart';
import 'package:mediapipe_gallery/main.dart';

import 'support/gallery_tiles.dart';

/// `required` fails when the SDK refuses the GPU, as on a phone; `optional`
/// records a refusal at creation; `skip` runs CPU only.
/// The iOS simulator needs `skip`: Google's iOS SDK aborts in its Metal
/// image-to-tensor conversion there (a failed check in
/// DrishtiMetalHelper copyCVMetalTextureWithGpuBuffer), a native crash no test
/// can record. So does the Android emulator: its SwiftShader GL accepts a GPU
/// task, then TFLite's GL delegate fails on the first frame
/// (GL_INVALID_ENUM from glGetBufferParameteri64v). GPU is a phone check on
/// both, as it is for Face Landmarker.
const _gpu = String.fromEnvironment('SDK_GPU', defaultValue: 'optional');

/// Google's official CPU landmarks for `thumb_up.jpg` (`mediapipe==1.0.0`,
/// macOS arm64 wheel), from the package's
/// `test/fixtures/landmark_tasks/official_reference.json`.
const _official = <(double, double)>[
  (0.638756, 0.671342), (0.634899, 0.536707), (0.574672, 0.412842), //
  (0.499685, 0.325514), (0.473628, 0.251028), (0.407497, 0.471301), //
  (0.337207, 0.467420), (0.441842, 0.509600), (0.480570, 0.518769), //
  (0.392183, 0.549520), (0.340471, 0.556102), (0.461523, 0.583108), //
  (0.470589, 0.564142), (0.392376, 0.618645), (0.343047, 0.628003), //
  (0.450040, 0.643008), (0.464002, 0.622156), (0.392316, 0.681880), //
  (0.357859, 0.698581), (0.426990, 0.698921), (0.444231, 0.687622),
];

/// Another runtime build and image decoder than the reference's, so the bound
/// is the cross-runtime one the Android face test uses for CPU against GPU.
const _crossRuntime = 0.03;

// Hand Landmarker through Google's official mobile SDKs: iOS through the
// package's Objective-C adapter, Android through
// mediapipe_flutter_vision_android. Runs on the iOS simulator and Android
// emulator in CI, and on phones.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'official SDK Hand Landmarker: reference, pixels, rotation, CPU and GPU',
    (tester) async {
      await tester.runAsync(() async {
        expect(Platform.isAndroid || Platform.isIOS, isTrue);
        if (Platform.isAndroid) {
          expect(
            handLandmarkerBackendFactory,
            isNotNull,
            reason: 'the Android SDK plugin must register automatically',
          );
        }
        final assets = await GalleryAssets.unpack();
        final model = await _model();
        final frame = await _sample('thumb_up.jpg');
        final references = <VisionDelegate, HandLandmarkerResult>{};
        for (final delegate in [
          VisionDelegate.cpu,
          if (_gpu != 'skip') VisionDelegate.gpu,
        ]) {
          final HandLandmarker task;
          try {
            task = await HandLandmarker.create(
              HandLandmarkerOptions(
                modelBytes: model,
                delegate: delegate,
                numHands: 2,
              ),
            );
          } on VisionTaskException catch (error) {
            if (delegate == VisionDelegate.cpu || _gpu == 'required') rethrow;
            _report('gpu_unavailable', {'error': error.message});
            continue;
          }
          try {
            final file = await task.detectImage(
              VisionImage.fromFile(assets.path('thumb_up.jpg')),
            );
            final official = _official.indexed.fold(0.0, (worst, entry) {
              final (i, (x, y)) = entry;
              final point = file.handLandmarks.single[i];
              return math.max(
                worst,
                math.max((point.x - x).abs(), (point.y - y).abs()),
              );
            });
            _hand(file);
            expect(file.handedness.single.first.categoryName, 'Right');
            expect(official, lessThan(_crossRuntime));
            final reference = await task.detectImage(frame.image);
            _hand(reference);
            references[delegate] = reference;
            final copied = reference.handLandmarks.single.first.x;
            for (final format in VisionPixelFormat.values) {
              final padded = await task.detectImage(_padded(frame, format));
              expect(
                _delta(reference, padded),
                lessThan(1e-5),
                reason: format.name,
              );
            }
            for (final turn in [90, 180, 270]) {
              final rotated = _rotate(frame, (360 - turn) % 360);
              final result = await task.detectImage(
                rotated,
                rotationDegrees: turn,
              );
              _hand(result);
              expect(result.imageWidth, rotated.width);
            }
            final blank = await task.detectImage(_blank());
            expect(blank.handLandmarks, isEmpty);
            expect(blank.handWorldLandmarks, isEmpty);
            expect(blank.handedness, isEmpty);
            expect(reference.handLandmarks.single.first.x, copied);
            _report('image', {
              'delegate': delegate.name,
              'official_max_delta': official,
              'handedness': file.handedness.single.first.score,
            });
          } finally {
            await task.dispose();
          }
          await task.dispose();
          await expectLater(task.detectImage(frame.image), throwsStateError);
        }
        if (references.length == 2) {
          final delta = _delta(
            references[VisionDelegate.cpu]!,
            references[VisionDelegate.gpu]!,
          );
          expect(delta, lessThan(_crossRuntime));
          _report('cpu_gpu', {'max_landmark_delta': delta});
        }
        await expectLater(
          HandLandmarker.create(
            HandLandmarkerOptions(modelBytes: Uint8List.fromList([1, 2, 3])),
          ),
          throwsA(isA<VisionTaskException>()),
        );
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'official SDK Hand Landmarker VIDEO: tracking, blank, queued frames',
    (tester) async {
      await tester.runAsync(() async {
        final assets = await GalleryAssets.unpack();
        final frame = await _sample('thumb_up.jpg');
        final task = await HandLandmarker.create(
          HandLandmarkerOptions(
            modelPath: assets.path('hand_landmarker.task'),
            runningMode: VisionRunningMode.video,
            numHands: 2,
          ),
        );
        try {
          await expectLater(task.detectImage(frame.image), throwsStateError);
          await expectLater(
            task.detectForVideo(frame.image, timestampMilliseconds: -1),
            throwsArgumentError,
          );
          final queued = await Future.wait([
            task.detectForVideo(frame.image, timestampMilliseconds: 0),
            task.detectForVideo(frame.image, timestampMilliseconds: 33),
          ]);
          expect(queued.map((r) => r.timestampMilliseconds), [0, 33]);
          queued.forEach(_hand);
          await expectLater(
            task.detectForVideo(frame.image, timestampMilliseconds: 33),
            throwsArgumentError,
          );
          for (var i = 2; i < 12; i++) {
            final result = await task.detectForVideo(
              frame.image,
              timestampMilliseconds: i * 33,
            );
            _hand(result);
            expect(result.timestampMilliseconds, i * 33);
          }
          final empty = await task.detectForVideo(
            _blank(),
            timestampMilliseconds: 400,
          );
          expect(empty.handLandmarks, isEmpty);
          _hand(
            await task.detectForVideo(frame.image, timestampMilliseconds: 433),
          );
          _report('video', {'hand_frames': 13, 'blank_frames': 1});
        } finally {
          await task.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets('gallery opens Live Hand Landmarker and runs frames', (
    tester,
  ) async {
    await tester.pumpWidget(const GalleryApp());
    final tile = await scrollToGalleryTile(tester, 'Live Hand Landmarker');
    expect(tile, findsOneWidget);
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LiveCameraView), findsOneWidget);
    final controller = tester
        .widget<LiveCameraView>(find.byType(LiveCameraView))
        .controller;
    // A simulator or emulator may have no camera; the demo must then report
    // that rather than fail. Where one exists, frames must flow.
    final deadline = DateTime.now().add(const Duration(seconds: 35));
    while (controller.processedFrames < 10 &&
        controller.error == null &&
        DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    _report('gallery', {
      'processed_frames': controller.processedFrames,
      'error': controller.error,
      'cameras': controller.cameras.length,
    });
    await tester.pump();
    if (controller.cameras.isEmpty) {
      expect(find.textContaining('No camera found'), findsOneWidget);
    } else {
      expect(controller.error, isNull);
      expect(controller.processedFrames, greaterThanOrEqualTo(10));
      expect(controller.result, isA<HandLandmarkerResult>());
    }
    await tester.runAsync(controller.close);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<Uint8List> _model() async {
  final bytes = await rootBundle.load('assets/models/hand_landmarker.task');
  return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}

typedef _Frame = ({int width, int height, Uint8List pixels, VisionImage image});

Future<_Frame> _sample(String name) async {
  final bytes = await rootBundle.load('assets/samples/$name');
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

/// [frame] in [format], with 16 bytes of row padding and opaque alpha.
VisionImage _padded(_Frame frame, VisionPixelFormat format) {
  final channels = format.channels;
  final stride = frame.width * channels + 16;
  final pixels = Uint8List(stride * frame.height);
  final bgra = format == VisionPixelFormat.bgra;
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final src = (y * frame.width + x) * 4;
      final dst = y * stride + x * channels;
      pixels[dst] = frame.pixels[src + (bgra ? 2 : 0)];
      pixels[dst + 1] = frame.pixels[src + 1];
      pixels[dst + 2] = frame.pixels[src + (bgra ? 0 : 2)];
      if (channels == 4) pixels[dst + 3] = 255;
    }
  }
  return VisionImage.fromPixels(
    pixels: pixels,
    width: frame.width,
    height: frame.height,
    format: format,
    bytesPerRow: stride,
  );
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

/// One hand with 21 finite image and world landmarks and a handedness.
void _hand(HandLandmarkerResult result) {
  expect(result.handLandmarks, hasLength(1));
  expect(result.handLandmarks.single, hasLength(21));
  expect(result.handWorldLandmarks.single, hasLength(21));
  expect(result.handedness.single, isNotEmpty);
  for (final point in [
    ...result.handLandmarks.single,
    ...result.handWorldLandmarks.single,
  ]) {
    expect(point.x.isFinite && point.y.isFinite && point.z.isFinite, isTrue);
  }
}

double _delta(HandLandmarkerResult a, HandLandmarkerResult b) {
  _hand(a);
  _hand(b);
  var maximum = 0.0;
  for (var i = 0; i < 21; i++) {
    final p = a.handLandmarks.single[i], q = b.handLandmarks.single[i];
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

void _report(String event, Map<String, Object?> data) {
  // Kept in the device log (logcat, the simulator console) for the record.
  // ignore: avoid_print
  print('SDK_HAND_LANDMARKER ${jsonEncode({'event': event, ...data})}');
}
