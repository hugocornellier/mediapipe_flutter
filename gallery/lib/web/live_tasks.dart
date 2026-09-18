import 'dart:typed_data';
import 'package:mediapipe_flutter_vision/web.dart';
import '../live/live_task.dart';

/// Browser transport for the same public FaceLandmarker task.
final class FaceLandmarkerLiveTask
    implements BrowserLiveTask<FaceLandmarkerResult> {
  FaceLandmarker? _task;
  @override
  String get name => 'Face Landmarker';
  @override
  Future<void> open(VisionDelegate delegate, Uint8List modelBytes) async {
    _task = await FaceLandmarker.create(
      FaceLandmarkerOptions(
        modelBytes: modelBytes,
        runningMode: VisionRunningMode.video,
        delegate: delegate,
        numFaces: 1,
      ),
    );
  }

  @override
  Future<FaceLandmarkerResult> detect(
    VisionImage frame,
    int timestamp, {
    required int rotationDegrees,
  }) => _task!.detectForVideo(
    frame,
    timestampMilliseconds: timestamp,
    rotationDegrees: rotationDegrees,
  );
  @override
  Future<FaceLandmarkerResult> detectBrowserFrame(
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
