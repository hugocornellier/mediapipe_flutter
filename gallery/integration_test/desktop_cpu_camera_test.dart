import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_gallery/live/live_camera_controller.dart';
import 'package:mediapipe_gallery/live/live_camera_view.dart';
import 'package:mediapipe_gallery/main.dart';

// Hosted runners have no physical webcam. Replace capture only: the gallery,
// controller, frame conversion, worker and Google's native CPU task are real.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native desktop camera plugin registers and enumerates devices', (
    tester,
  ) async {
    expect(Platform.isLinux || Platform.isWindows, isTrue);
    expect(
      CameraPlatform.instance.runtimeType.toString(),
      'CameraDesktopPlugin',
    );
    expect(CameraPlatform.instance.supportsImageStreaming(), isTrue);
    await tester.runAsync(() async {
      final cameras = await CameraPlatform.instance.availableCameras();
      // An empty list is expected on hosted CI; enumeration must still work.
      expect(cameras, isA<List<CameraDescription>>());
    });
  });

  testWidgets(
    'gallery CPU camera: RGBA/BGRA, switching, restart and cleanup',
    (tester) async {
      final original = CameraPlatform.instance;
      final frames = await tester.runAsync(_portraitFrames);
      final camera = _SuppliedCamera(frames!);
      CameraPlatform.instance = camera;
      LiveCameraController<Object?>? controller;
      try {
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
        expect(find.text('GPU'), findsNothing);
        await tester.tap(find.text('Live Face Landmarker'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        controller = tester
            .widget<LiveCameraView>(find.byType(LiveCameraView))
            .controller;
        final live = controller;
        final firstFrames = <String, FaceLandmarkerResult>{};
        live.addListener(() {
          final result = live.result;
          if (live.processedFrames == 1 && result is FaceLandmarkerResult) {
            firstFrames.putIfAbsent(live.description!.name, () => result);
          }
        });
        camera.deliverFrames = true;
        await _frames(tester, live);
        await tester.pump();
        expect(find.text('GPU'), findsNothing);
        expect(find.byType(SegmentedButton<VisionDelegate>), findsNothing);
        expect(live.delegate, VisionDelegate.cpu);
        expect(live.frameRotationDegrees, 0);

        // Switch from the padded RGBA camera to padded BGRA without closing the
        // page. The same portrait must retain its face geometry and color order.
        await tester.tap(find.byTooltip('Switch to back camera'));
        await tester.pump();
        await _frames(tester, live);
        await tester.pump();
        // Later VIDEO results depend on how many tracking frames arrived while
        // the UI was pumping. Compare the first frame of each fresh task.
        final before = firstFrames['supplied-rgba']!.faceLandmarks.single;
        final after = firstFrames['supplied-bgra']!.faceLandmarks.single;
        for (var i = 0; i < before.length; i++) {
          expect(after[i].x, closeTo(before[i].x, 1e-4));
          expect(after[i].y, closeTo(before[i].y, 1e-4));
        }
        expect(live.description!.name, 'supplied-bgra');
        expect(camera.disposed, 1);

        expect(find.byType(FilledButton), findsNothing);
        await tester.runAsync(live.stop);
        await tester.runAsync(() async {
          while (live.changing) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pump();
        expect(live.running, isFalse);
        expect(camera.activeStreams, 0);
        await tester.runAsync(live.start);
        await _frames(tester, live);
        await tester.pump();
        expect(live.running, isTrue);
        expect(live.delegate, VisionDelegate.cpu);
      } finally {
        await tester.runAsync(() async => await controller?.close());
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        CameraPlatform.instance = original;
      }
      expect(camera.activeStreams, 0);
      expect(camera.disposed, 3);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _frames(
  WidgetTester tester,
  LiveCameraController<Object?> controller,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while ((controller.changing || controller.processedFrames < 12) &&
      controller.error == null &&
      DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 33));
  }
  expect(controller.error, isNull);
  expect(controller.processedFrames, greaterThanOrEqualTo(12));
  final result = controller.result! as FaceLandmarkerResult;
  expect(result.faceLandmarks.single, hasLength(478));
  expect(result.timestampMilliseconds, greaterThan(0));
  for (final point in result.faceLandmarks.single) {
    expect(point.x.isFinite && point.y.isFinite && point.z.isFinite, isTrue);
  }
}

Future<List<CameraImageData>> _portraitFrames() async {
  final bytes = await rootBundle.load('assets/samples/portrait.jpg');
  final codec = await ui.instantiateImageCodec(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
  final image = (await codec.getNextFrame()).image;
  try {
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final source = rgba.buffer.asUint8List(
      rgba.offsetInBytes,
      rgba.lengthInBytes,
    );
    final stride = image.width * 4 + 16;
    return [
      for (final bgra in [false, true])
        CameraImageData(
          format: CameraImageFormat(
            ImageFormatGroup.bgra8888,
            raw: bgra ? 'BGRA' : 'RGBA',
          ),
          width: image.width,
          height: image.height,
          planes: [
            CameraImagePlane(
              bytes: _pad(source, image.width, image.height, stride, bgra),
              bytesPerRow: stride,
              bytesPerPixel: 4,
            ),
          ],
        ),
    ];
  } finally {
    image.dispose();
    codec.dispose();
  }
}

Uint8List _pad(Uint8List source, int width, int height, int stride, bool bgra) {
  final result = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final src = (y * width + x) * 4, dst = y * stride + x * 4;
      result[dst] = source[src + (bgra ? 2 : 0)];
      result[dst + 1] = source[src + 1];
      result[dst + 2] = source[src + (bgra ? 0 : 2)];
      result[dst + 3] = 255;
    }
  }
  return result;
}

final class _SuppliedCamera extends CameraPlatform {
  _SuppliedCamera(this.frames);
  final List<CameraImageData> frames;
  final _initialized = <int, StreamController<CameraInitializedEvent>>{};
  final _errors = StreamController<CameraErrorEvent>.broadcast();
  final _indices = <int, int>{};
  int _nextId = 0;
  int activeStreams = 0;
  int disposed = 0;
  bool deliverFrames = false;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'supplied-rgba',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 0,
    ),
    CameraDescription(
      name: 'supplied-bgra',
      lensDirection: CameraLensDirection.external,
      sensorOrientation: 0,
    ),
  ];

  @override
  Future<int> createCamera(
    CameraDescription description,
    ResolutionPreset? preset, {
    bool enableAudio = false,
  }) async {
    final id = _nextId++;
    _indices[id] = description.name == 'supplied-rgba' ? 0 : 1;
    _initialized[id] = StreamController<CameraInitializedEvent>();
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    final frame = frames[_indices[cameraId]!];
    _initialized[cameraId]!.add(
      CameraInitializedEvent(
        cameraId,
        frame.width.toDouble(),
        frame.height.toDouble(),
        ExposureMode.auto,
        false,
        FocusMode.auto,
        false,
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initialized[cameraId]!.stream;
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      _errors.stream.where((event) => event.cameraId == cameraId);
  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      const Stream.empty();
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      Stream.value(
        const DeviceOrientationChangedEvent(DeviceOrientation.landscapeLeft),
      );
  @override
  bool supportsImageStreaming() => true;
  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.black);

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    Timer? timer;
    late final StreamController<CameraImageData> stream;
    stream = StreamController<CameraImageData>(
      onListen: () {
        activeStreams++;
        timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
          if (deliverFrames) stream.add(frames[_indices[cameraId]!]);
        });
      },
      onCancel: () {
        timer?.cancel();
        activeStreams--;
      },
    );
    return stream.stream;
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposed++;
    await _initialized.remove(cameraId)!.close();
    _indices.remove(cameraId);
  }
}
