import '../../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Hand Landmarker installed by the web adapter.
final class HandLandmarker extends SdkVisionTask<HandLandmarkerResult> {
  HandLandmarker._(super.backend, super.runningMode, super.delegate)
    : super(name: 'HandLandmarker');

  /// Creates a task through the registered official browser adapter.
  static Future<HandLandmarker> create(HandLandmarkerOptions options) async =>
      HandLandmarker._(
        await requireBrowserFactory(handLandmarkerBackendFactory)(options),
        options.runningMode,
        options.delegate,
      );
}
