import 'dart:typed_data';

import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'live_camera_controller.dart';

/// Each adapter is only the two things that differ between live demos: how the
/// task is built, and how one frame runs through it.
final class FaceLandmarkerLiveTask implements LiveTask<FaceLandmarkerResult> {
  FaceLandmarker? _task;

  @override
  String get name => 'Face Landmarker';

  @override
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await FaceLandmarker.create(
      FaceLandmarkerOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
      ),
    );
  }

  @override
  Future<FaceLandmarkerResult> detect(VisionImage frame, int timestamp) =>
      _task!.detectForVideo(frame, timestampMilliseconds: timestamp);

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

final class HandLandmarkerLiveTask implements LiveTask<HandLandmarkerResult> {
  HandLandmarker? _task;

  @override
  String get name => 'Hand Landmarker';

  @override
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await HandLandmarker.create(
      HandLandmarkerOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
        numHands: 2,
      ),
    );
  }

  @override
  Future<HandLandmarkerResult> detect(VisionImage frame, int timestamp) =>
      _task!.detectForVideo(frame, timestampMilliseconds: timestamp);

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

final class PoseLandmarkerLiveTask implements LiveTask<PoseLandmarkerResult> {
  PoseLandmarker? _task;

  @override
  String get name => 'Pose Landmarker';

  @override
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await PoseLandmarker.create(
      PoseLandmarkerOptions(
        delegate: delegate,
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
      ),
    );
  }

  @override
  Future<PoseLandmarkerResult> detect(VisionImage frame, int timestamp) =>
      _task!.detectForVideo(frame, timestampMilliseconds: timestamp);

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}
