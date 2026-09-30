import '../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Holistic Landmarker installed by the web adapter.
///
/// ```dart
/// final task = await HolisticLandmarker.create(
///   HolisticLandmarkerOptions(model: VisionModels.holisticLandmarker),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.detectImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class HolisticLandmarker extends SdkVisionTask<HolisticLandmarkerResult> {
  HolisticLandmarker._(super.backend, super.runningMode, super.delegate)
    : super(name: 'HolisticLandmarker');

  /// Creates a task through the registered official browser adapter.
  static Future<HolisticLandmarker> create(
    HolisticLandmarkerOptions options,
  ) async {
    await options.prepareModel();
    return HolisticLandmarker._(
      await requireBrowserFactory(holisticLandmarkerBackendFactory)(options),
      options.runningMode,
      options.delegate,
    );
  }
}
