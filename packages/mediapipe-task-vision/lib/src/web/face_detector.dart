import '../../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Face Detector installed by the web adapter.
final class FaceDetector extends SdkVisionTask<FaceDetectorResult> {
  FaceDetector._(super.backend, super.runningMode, super.delegate)
    : super(name: 'FaceDetector');

  /// Creates a task through the registered official browser adapter.
  static Future<FaceDetector> create(FaceDetectorOptions options) async =>
      FaceDetector._(
        await requireBrowserFactory(faceDetectorBackendFactory)(options),
        options.runningMode,
        options.delegate,
      );
}
