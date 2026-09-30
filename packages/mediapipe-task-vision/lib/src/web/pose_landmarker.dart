import '../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Pose Landmarker installed by the web adapter.
///
/// ```dart
/// final task = await PoseLandmarker.create(
///   PoseLandmarkerOptions(model: VisionModels.poseLandmarker),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.detectImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class PoseLandmarker extends SdkVisionTask<PoseLandmarkerResult> {
  PoseLandmarker._(super.backend, super.runningMode, super.delegate)
    : super(name: 'PoseLandmarker');

  /// Creates a task through the registered official browser adapter.
  static Future<PoseLandmarker> create(PoseLandmarkerOptions options) async {
    await options.prepareModel();
    return PoseLandmarker._(
      await requireBrowserFactory(poseLandmarkerBackendFactory)(options),
      options.runningMode,
      options.delegate,
    );
  }
}
