import '../../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Pose Landmarker installed by the web adapter.
final class PoseLandmarker extends SdkVisionTask<PoseLandmarkerResult> {
  PoseLandmarker._(super.backend, super.runningMode, super.delegate)
    : super(name: 'PoseLandmarker');

  /// Creates a task through the registered official browser adapter.
  static Future<PoseLandmarker> create(PoseLandmarkerOptions options) async =>
      PoseLandmarker._(
        await requireBrowserFactory(poseLandmarkerBackendFactory)(options),
        options.runningMode,
        options.delegate,
      );
}
