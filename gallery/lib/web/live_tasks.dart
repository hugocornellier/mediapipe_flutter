import 'dart:typed_data';
import 'package:mediapipe_flutter_vision/web.dart';
import '../live/live_task.dart';

/// Browser transport shared by every public task on the official web adapter:
/// each demo supplies only its name and how its task is built.
abstract base class _WebLiveTask<R> implements BrowserLiveTask<R> {
  SdkVisionTask<R>? _task;

  /// Creates the VIDEO-mode task.
  Future<SdkVisionTask<R>> create(VisionDelegate delegate, Uint8List model);

  @override
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await create(delegate, modelBytes);
  }

  @override
  Future<R> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );

  @override
  Future<R> detectBrowserFrame(
    Object frame,
    int width,
    int height,
    int timestamp,
  ) => _task!.detectBrowserFrame(
    frame,
    width: width,
    height: height,
    timestampMilliseconds: timestamp,
  );

  @override
  Future<void> close() async {
    final task = _task;
    _task = null;
    await task?.dispose();
  }
}

/// Browser transport for the same public FaceLandmarker task.
final class FaceLandmarkerLiveTask extends _WebLiveTask<FaceLandmarkerResult> {
  @override
  String get name => 'Face Landmarker';

  @override
  Future<FaceLandmarker> create(VisionDelegate delegate, Uint8List model) =>
      FaceLandmarker.create(
        FaceLandmarkerOptions(
          modelBytes: model,
          runningMode: VisionRunningMode.video,
          delegate: delegate,
          numFaces: 1,
        ),
      );
}

/// Browser transport for the same public HandLandmarker task. Hands counts
/// hands, not people, as in the native demo.
final class HandLandmarkerLiveTask extends _WebLiveTask<HandLandmarkerResult> {
  @override
  String get name => 'Hand Landmarker';

  @override
  Future<HandLandmarker> create(VisionDelegate delegate, Uint8List model) =>
      HandLandmarker.create(
        HandLandmarkerOptions(
          modelBytes: model,
          runningMode: VisionRunningMode.video,
          delegate: delegate,
          numHands: 2,
        ),
      );
}
