import 'dart:async';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_gallery/live/live_camera_controller.dart';

import 'support/scripted_camera.dart';

// The controller's lifecycle rules, pinned without hardware or native code.
// Capture is a scripted camera platform and the task completes inference when
// the test says so, which is how start-during-stop, switch-during-inference and
// dispose-mid-frame become deterministic rather than racy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ScriptedCamera camera;
  late ScriptedTask task;
  late LiveCameraController<int> controller;
  late CameraPlatform original;

  setUp(() {
    original = CameraPlatform.instance;
    camera = ScriptedCamera();
    CameraPlatform.instance = camera;
    task = ScriptedTask();
    controller = LiveCameraController<int>(task);
    // Any asset will do for the fake task; the controller only loads it.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'flutter/assets',
          (_) async => ByteData.sublistView(Uint8List.fromList([1, 2, 3])),
        );
  });

  tearDown(() async {
    // close() drains in-flight inference, so release anything a test left.
    while (task.pending.isNotEmpty) {
      task.finish();
    }
    await controller.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    CameraPlatform.instance = original;
  });

  Future<void> started({VisionDelegate? delegate}) async {
    await controller.findCameras();
    await controller.start(delegate: delegate, modelAsset: 'model.task');
    expect(controller.error, isNull);
    expect(controller.running, isTrue);
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('opens the task, starts capture and prefers the front camera', () async {
    await started();
    expect(controller.description!.name, 'front');
    expect(task.opened, [VisionDelegate.cpu]);
    expect(camera.created, ['front']);
    expect(camera.activeStreams, 1);
    expect(controller.changing, isFalse);
  });

  test('runs the newest frame that arrived during inference next', () async {
    await started();
    camera.emit();
    await settle();
    expect(task.detectCalls, 1);
    camera.emit(ScriptedCamera.smallFrame(width: 6));
    camera.emit(ScriptedCamera.smallFrame(width: 8));
    await settle();
    expect(task.detectCalls, 1, reason: 'busy: no second inference');
    expect(controller.skippedFrames, 1, reason: 'the newer frame replaced it');
    expect(controller.processedFrames, 0);
    task.finish(7);
    await settle();
    expect(controller.processedFrames, 1);
    expect(controller.result, 7);
    expect(task.detectCalls, 2, reason: 'the waiting frame runs at once');
    task.finish(8);
    await settle();
    expect(controller.frameSize!.width, 8, reason: 'the newest frame ran');
    expect(controller.recentFrames, 2);
    camera.emit();
    await settle();
    expect(task.detectCalls, 3, reason: 'idle again: the next frame runs');
  });

  test('warms up on the sample, then a blank frame, before capture', () async {
    // A 2x2 grey PNG: the warm-up decodes the sample it is given.
    final png = Uint8List.fromList([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      13,
      73,
      72,
      68,
      82,
      0,
      0,
      0,
      2, //
      0, 0, 0, 2, 8, 6, 0, 0, 0, 114, 182, 13, 36, 0, 0, 0, 17, 73, 68, 65, //
      84,
      120,
      156,
      99,
      104,
      104,
      104,
      248,
      15,
      194,
      12,
      48,
      6,
      0,
      86,
      244,
      9, //
      253, 75, 75, 233, 44, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130, //
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'flutter/assets',
          (_) async => ByteData.sublistView(png),
        );
    await controller.findCameras();
    final starting = controller.start(
      modelAsset: 'model.task',
      warmUpSample: 'sample.png',
    );
    for (var frame = 0; frame < 2; frame++) {
      while (task.pending.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(camera.activeStreams, 0, reason: 'no capture during warm-up');
      task.finish();
    }
    await starting;
    expect(controller.running, isTrue);
    expect(task.timestamps, [0, 1]);
    expect(task.forgot, 1, reason: 'the camera finds the task fresh');
    expect(controller.processedFrames, 0, reason: 'warm-up is not shown');
    camera.emit();
    await settle();
    expect(task.timestamps.last, greaterThan(1));
  });

  test('timestamps strictly increase even within one millisecond', () async {
    await started();
    for (var i = 0; i < 5; i++) {
      camera.emit();
      await settle();
      task.finish();
      await settle();
    }
    expect(task.timestamps, hasLength(5));
    for (var i = 1; i < task.timestamps.length; i++) {
      expect(task.timestamps[i], greaterThan(task.timestamps[i - 1]));
    }
  });

  test('stop waits for in-flight inference, then closes the task', () async {
    await started();
    camera.emit();
    await settle();
    expect(task.pending, hasLength(1));
    final stopping = controller.stop();
    expect(controller.running, isFalse);
    expect(controller.changing, isTrue);
    await settle();
    await settle();
    expect(camera.disposed, 1, reason: 'capture is released first');
    expect(task.closed, 0, reason: 'the task outlives its in-flight frame');
    task.finish(9);
    await stopping;
    expect(task.closed, 1);
    expect(controller.changing, isFalse);
    expect(controller.result, isNull, reason: 'a late result is discarded');
    expect(controller.processedFrames, 0);
    expect(camera.activeStreams, 0);
  });

  test('a superseded start releases what it opened and never runs', () async {
    await controller.findCameras();
    camera.initializeGate = Completer<void>();
    final first = controller.start(
      delegate: VisionDelegate.cpu,
      modelAsset: 'model.task',
    );
    await settle();
    expect(task.opened, [VisionDelegate.cpu]);
    final second = controller.start(delegate: VisionDelegate.gpu);
    camera.initializeGate!.complete();
    camera.initializeGate = null;
    await Future.wait([first, second]);
    expect(task.opened, [VisionDelegate.cpu, VisionDelegate.gpu]);
    expect(task.closed, 1, reason: 'the CPU task was closed, not leaked');
    expect(camera.disposed, 1);
    expect(camera.created, ['front', 'front']);
    expect(controller.delegate, VisionDelegate.gpu);
    expect(controller.running, isTrue);
    expect(controller.error, isNull);
  });

  test('an inference failure stops capture and reports the message', () async {
    await started();
    task.failure = const FaceLandmarkerException('graph aborted');
    camera.emit();
    await settle();
    await settle();
    await settle();
    expect(controller.running, isFalse);
    expect(controller.error, contains('graph aborted'));
    await controller.stop();
    expect(task.closed, 1);
    expect(camera.disposed, 1);
    expect(camera.activeStreams, 0);
  });

  test('a refused GPU falls back to CPU with a visible notice', () async {
    task.openFailure = (
      VisionDelegate.gpu,
      const FaceLandmarkerException(
        'Service "kGpuService" ... GPU emulation detected',
        gpuUnavailable: true,
      ),
    );
    await controller.findCameras();
    await controller.start(
      delegate: VisionDelegate.gpu,
      modelAsset: 'model.task',
    );
    // The CPU restart is queued behind the refused start; let it run.
    for (var i = 0; i < 20 && !controller.running; i++) {
      await settle();
    }
    expect(task.opened, [VisionDelegate.gpu, VisionDelegate.cpu]);
    expect(controller.delegate, VisionDelegate.cpu);
    expect(controller.running, isTrue);
    expect(controller.error, isNull);
    expect(controller.notice, contains('GPU unavailable, using CPU'));
    expect(controller.notice, contains('GPU emulation detected'));
  });

  test(
    'a refused GPU on a generic task, such as hand, also falls back',
    () async {
      task.openFailure = (
        VisionDelegate.gpu,
        const VisionTaskException(
          'Service "kGpuService" ... Unable to initialize EGL',
          gpuUnavailable: true,
        ),
      );
      await controller.findCameras();
      await controller.start(
        delegate: VisionDelegate.gpu,
        modelAsset: 'model.task',
      );
      for (var i = 0; i < 20 && !controller.running; i++) {
        await settle();
      }
      expect(task.opened, [VisionDelegate.gpu, VisionDelegate.cpu]);
      expect(controller.running, isTrue);
      expect(controller.notice, contains('Unable to initialize EGL'));
    },
  );

  test('other GPU failures are errors, never a silent fallback', () async {
    task.openFailure = (
      VisionDelegate.gpu,
      const FaceLandmarkerException('model is corrupt'),
    );
    await controller.findCameras();
    await controller.start(
      delegate: VisionDelegate.gpu,
      modelAsset: 'model.task',
    );
    expect(task.opened, [VisionDelegate.gpu]);
    expect(controller.running, isFalse);
    expect(controller.error, contains('model is corrupt'));
    expect(controller.notice, isNull);
  });

  test('a camera error while running stops capture', () async {
    await started();
    camera.fail('Camera disconnected');
    await settle();
    await settle();
    expect(controller.running, isFalse);
    expect(controller.error, 'Camera disconnected');
    await controller.stop();
    expect(camera.disposed, 1);
  });

  test('switching cameras restarts capture on the other lens', () async {
    await started();
    await controller.switchCamera();
    expect(controller.description!.name, 'back');
    expect(controller.isFrontCamera, isFalse);
    expect(camera.created, ['front', 'back']);
    expect(camera.disposed, 1);
    expect(task.opened, hasLength(2));
    expect(task.closed, 1);
    expect(controller.running, isTrue);
  });

  test(
    'switching skips additional cameras facing the same direction',
    () async {
      camera = ScriptedCamera(
        cameras: const [
          CameraDescription(
            name: 'front',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 0,
          ),
          CameraDescription(
            name: 'back-wide',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 0,
          ),
          CameraDescription(
            name: 'back-ultrawide',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 0,
          ),
        ],
      );
      CameraPlatform.instance = camera;
      controller = LiveCameraController<int>(task);

      await started();
      await controller.switchCamera();
      await controller.switchCamera();

      expect(camera.created, ['front', 'back-wide', 'front']);
    },
  );

  test('switching while stopped only changes the selection', () async {
    await controller.findCameras();
    await controller.switchCamera();
    expect(controller.description!.name, 'back');
    expect(camera.created, isEmpty);
    expect(task.opened, isEmpty);
  });

  test('start re-uses the previous delegate and model by default', () async {
    await started(delegate: VisionDelegate.gpu);
    await controller.stop();
    await controller.start();
    expect(task.opened, [VisionDelegate.gpu, VisionDelegate.gpu]);
    expect(controller.running, isTrue);
  });

  test(
    'close is idempotent, drains inference and silences listeners',
    () async {
      await started();
      camera.emit();
      await settle();
      var notified = 0;
      controller.addListener(() => notified++);
      final closing = controller.close();
      expect(identical(controller.close(), closing), isTrue);
      await settle();
      await settle();
      expect(task.closed, 0, reason: 'still draining the in-flight frame');
      task.finish();
      await closing;
      expect(task.closed, 1);
      expect(camera.disposed, 1);
      expect(camera.activeStreams, 0);
      expect(controller.camera, isNull);
      expect(
        notified,
        1,
        reason: 'exactly one notification drops the preview before dispose',
      );
      await expectLater(
        controller.start(),
        throwsA(isA<StateError>()),
        reason: 'a closed controller refuses to start',
      );
    },
  );

  test('dispose during a start in progress leaves nothing open', () async {
    await controller.findCameras();
    camera.initializeGate = Completer<void>();
    final starting = controller.start(modelAsset: 'model.task');
    await settle();
    controller.dispose();
    camera.initializeGate!.complete();
    camera.initializeGate = null;
    await starting;
    await settle();
    expect(task.closed, 1);
    expect(camera.disposed, 1);
    expect(camera.activeStreams, 0);
    expect(controller.running, isFalse);
  });
}
