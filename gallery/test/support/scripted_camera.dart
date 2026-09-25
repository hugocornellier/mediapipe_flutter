import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_gallery/live/live_task.dart';
import 'package:mediapipe_gallery/live/task_settings.dart';

/// A camera platform the test drives by hand: frames arrive when the test
/// says, initialization can be held open, and every lifecycle call is counted.
final class ScriptedCamera extends CameraPlatform {
  ScriptedCamera({this.cameras = defaultCameras});

  static const defaultCameras = [
    CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 0,
    ),
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 0,
    ),
  ];

  final List<CameraDescription> cameras;
  final _initialized = <int, StreamController<CameraInitializedEvent>>{};
  final _errors = StreamController<CameraErrorEvent>.broadcast();
  final _streams = <int, StreamController<CameraImageData>>{};
  final created = <String>[];
  int _nextId = 0;
  int disposed = 0;
  int activeStreams = 0;

  /// When set, `initializeCamera` waits on it before reporting ready.
  Completer<void>? initializeGate;

  /// Delivers one frame to every active stream.
  void emit([CameraImageData? frame]) {
    for (final stream in _streams.values) {
      stream.add(frame ?? smallFrame());
    }
  }

  /// Reports a runtime camera failure to the owning controller.
  void fail(String description) {
    for (final id in _streams.keys) {
      _errors.add(CameraErrorEvent(id, description));
    }
  }

  /// A 4x4 padded BGRA frame, small enough to build hundreds of.
  static CameraImageData smallFrame({int width = 4, int height = 4}) {
    final stride = width * 4 + 8;
    return CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 'BGRA'),
      width: width,
      height: height,
      planes: [
        CameraImagePlane(
          bytes: Uint8List(stride * height),
          bytesPerRow: stride,
          bytesPerPixel: 4,
        ),
      ],
    );
  }

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCamera(
    CameraDescription description,
    ResolutionPreset? preset, {
    bool enableAudio = false,
  }) async {
    final id = _nextId++;
    created.add(description.name);
    _initialized[id] = StreamController<CameraInitializedEvent>();
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initializeGate?.future;
    _initialized[cameraId]!.add(
      CameraInitializedEvent(
        cameraId,
        4,
        4,
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
        const DeviceOrientationChangedEvent(DeviceOrientation.portraitUp),
      );
  @override
  bool supportsImageStreaming() => true;
  @override
  Widget buildPreview(int cameraId) => const SizedBox.shrink();

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    late final StreamController<CameraImageData> stream;
    stream = StreamController<CameraImageData>(
      onListen: () {
        activeStreams++;
        _streams[cameraId] = stream;
      },
      onCancel: () {
        activeStreams--;
        _streams.remove(cameraId);
      },
    );
    return stream.stream;
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposed++;
    await _initialized.remove(cameraId)?.close();
  }
}

/// A task whose inference the test completes by hand.
final class ScriptedTask implements LiveTask<int>, StatefulLiveTask {
  @override
  final settings = TaskSettingValues('scripted');

  final opened = <VisionDelegate>[];

  /// Times the controller asked the task to forget the frames it has seen.
  int forgot = 0;
  final timestamps = <int>[];
  final rotations = <int>[];
  int closed = 0;
  int detectCalls = 0;

  /// Pending inferences, oldest first; complete one to release a frame.
  final pending = <Completer<int>>[];

  /// When set, every detect call throws this instead of waiting.
  Object? failure;

  /// When set, opening with that delegate throws this error.
  (VisionDelegate, Object)? openFailure;

  @override
  String get name => 'scripted';

  @override
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    opened.add(delegate);
    if (openFailure case (
      final refused,
      final error,
    ) when refused == delegate) {
      throw error;
    }
  }

  @override
  Future<int> detect(
    VisionImage frame,
    int timestampMilliseconds, {
    required int rotationDegrees,
  }) {
    detectCalls++;
    timestamps.add(timestampMilliseconds);
    rotations.add(rotationDegrees);
    if (failure != null) return Future.error(failure!);
    final completer = Completer<int>();
    pending.add(completer);
    return completer.future;
  }

  /// Completes the oldest in-flight inference.
  void finish([int value = 1]) => pending.removeAt(0).complete(value);

  @override
  void forgetFrames() => forgot++;

  @override
  Future<void> close() async {
    closed++;
  }
}
