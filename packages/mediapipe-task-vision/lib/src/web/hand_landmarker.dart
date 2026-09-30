import '../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Hand Landmarker installed by the web adapter.
///
/// ```dart
/// final task = await HandLandmarker.create(
///   HandLandmarkerOptions(model: VisionModels.handLandmarker),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.detectImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class HandLandmarker extends SdkVisionTask<HandLandmarkerResult> {
  HandLandmarker._(super.backend, super.runningMode, super.delegate)
    : super(name: 'HandLandmarker');

  /// Creates a task through the registered official browser adapter.
  static Future<HandLandmarker> create(HandLandmarkerOptions options) async {
    await options.prepareModel();
    return HandLandmarker._(
      await requireBrowserFactory(handLandmarkerBackendFactory)(options),
      options.runningMode,
      options.delegate,
    );
  }
}
