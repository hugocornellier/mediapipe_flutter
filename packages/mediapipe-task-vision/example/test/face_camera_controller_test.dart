import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_face_camera/face_camera_controller.dart';
import 'package:mediapipe_face_camera/main.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

const _description = CameraDescription(
  name: 'Fixture camera',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 0,
);

class FixtureCamera extends CameraPlatform {
  final frames = StreamController<CameraImageData>.broadcast(sync: true);
  final errors = StreamController<CameraErrorEvent>.broadcast();
  int created = 0;
  int disposed = 0;
  bool denyAccess = false;
  Completer<void>? initializeGate;

  @override
  Future<List<CameraDescription>> availableCameras() async => [_description];
  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings settings,
  ) async {
    expect(settings.enableAudio, isFalse);
    return ++created;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initializeGate?.future;
    if (denyAccess) {
      throw CameraException('CameraAccessDenied', 'Denied for this test');
    }
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          301,
          209,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  bool supportsImageStreaming() => true;
  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) => frames.stream;
  @override
  Future<void> dispose(int cameraId) async {
    disposed++;
  }

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.black);
}

Future<void> _until(bool Function() ready) async {
  final timer = Stopwatch()..start();
  while (!ready()) {
    if (timer.elapsed > const Duration(seconds: 10)) {
      fail('Camera state did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

CameraImageData _portrait() {
  final rgb = File(
    '../test/fixtures/face_detection/portrait-301x209.rgb',
  ).readAsBytesSync();
  const stride = 301 * 4 + 12;
  final bgra = Uint8List(stride * 209);
  for (var y = 0; y < 209; y++) {
    for (var x = 0; x < 301; x++) {
      final source = (y * 301 + x) * 3;
      final destination = y * stride + x * 4;
      bgra[destination] = rgb[source + 2];
      bgra[destination + 1] = rgb[source + 1];
      bgra[destination + 2] = rgb[source];
      bgra[destination + 3] = 255;
    }
  }
  return CameraImageData(
    format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 'BGRA'),
    width: 301,
    height: 209,
    planes: [
      CameraImagePlane(bytes: bgra, bytesPerRow: stride, bytesPerPixel: 4),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureCamera platform;
  late CameraPlatform previous;
  late FaceCameraController session;
  var pageOwnsSession = false;
  setUp(() {
    pageOwnsSession = false;
    previous = CameraPlatform.instance;
    platform = FixtureCamera();
    CameraPlatform.instance = platform;
    session = FaceCameraController();
  });
  tearDown(() async {
    if (!pageOwnsSession) {
      await session.close();
      session.dispose();
    }
    CameraPlatform.instance = previous;
  });

  test(
    'camera frames reach official VIDEO inference, busy frames are skipped, and capture restarts',
    () async {
      await session.start(_description);
      expect(session.error, isNull);
      expect(session.running, isTrue);
      final image = _portrait();
      for (var i = 0; i < 12; i++) {
        platform.frames.add(image);
      }
      await _until(() => session.processedFrames == 1 || session.error != null);
      expect(session.error, isNull);
      expect(session.skippedFrames, 11);
      expect(session.result!.faceLandmarks, hasLength(1));
      expect(session.result!.faceLandmarks.single, hasLength(478));
      final timestamp = session.result!.timestampMilliseconds!;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      platform.frames.add(image);
      await _until(() => session.processedFrames == 2);
      expect(session.result!.timestampMilliseconds, greaterThan(timestamp));
      // Stop with another inference potentially in flight; late results cannot
      // restore the stopped UI or keep the camera stream subscribed.
      platform.frames.add(image);
      await session.stop();
      expect(session.running, isFalse);
      expect(session.result, isNull);
      expect(platform.frames.hasListener, isFalse);
      expect(platform.disposed, 1);
      // Switch backend after draining the old task, then switch back below.
      await session.start(_description, delegate: VisionDelegate.gpu);
      expect(session.delegate, VisionDelegate.gpu);
      expect(session.error, isNull);
      platform.frames.add(image);
      await _until(() => session.processedFrames == 1);
      expect(session.result!.faceLandmarks, hasLength(1));
      await session.start(_description, delegate: VisionDelegate.cpu);
      expect(session.delegate, VisionDelegate.cpu);
      platform.frames.add(image);
      await _until(() => session.processedFrames == 1);
      expect(session.result!.faceLandmarks.single, hasLength(478));
    },
  );

  test(
    'stop during camera initialization cancels capture and releases resources',
    () async {
      platform.initializeGate = Completer<void>();
      final starting = session.start(_description);
      await _until(() => platform.created == 1);
      final stopping = session.stop();
      platform.initializeGate!.complete();
      await Future.wait([starting, stopping]);
      expect(session.running, isFalse);
      expect(session.changing, isFalse);
      expect(platform.disposed, 1);
      expect(platform.frames.hasListener, isFalse);
    },
  );

  test('permission denial leaves a recoverable stopped session', () async {
    platform.denyAccess = true;
    await session.start(_description);
    expect(session.running, isFalse);
    expect(session.error, contains('System Settings'));
    expect(platform.disposed, 1);
    platform.denyAccess = false;
    await session.start(_description);
    expect(session.error, isNull);
    expect(session.running, isTrue);
  });

  testWidgets('camera page starts idle without capturing', (tester) async {
    pageOwnsSession = true;
    await tester.pumpWidget(FaceCameraApp(controller: session));
    await tester.pumpAndSettle();
    expect(find.text('Start camera'), findsOneWidget);
    expect(find.text('Fixture camera'), findsOneWidget);
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('GPU (Metal)'), findsOneWidget);
    await tester.tap(find.text('GPU (Metal)'));
    await tester.pumpAndSettle();
    expect(platform.created, 0);
    await tester.runAsync(session.close);
    await tester.pumpWidget(const SizedBox());
  });
}
