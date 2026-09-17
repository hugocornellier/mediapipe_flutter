import 'dart:typed_data';

import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

import 'live_camera_controller.dart';

/// Subjects each live demo tracks. Ask for what the demo needs and no more:
/// MediaPipe only skips its detector once tracking reaches the configured
/// maximum, so an inflated count keeps detection running every frame for a
/// scene that never reaches it. Hands counts hands, not people.
const _faces = 1;
const _hands = 2;
const _poses = 1;

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
        numFaces: _faces,
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
        numHands: _hands,
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
        numPoses: _poses,
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
