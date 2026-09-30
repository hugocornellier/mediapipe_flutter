import '../face_landmarker_backend.dart';
import '../interface/face_landmarker_types.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser task installed by the Flutter web adapter.
///
/// ```dart
/// final task = await FaceLandmarker.create(
///   FaceLandmarkerOptions(model: VisionModels.faceLandmarker),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.detectImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class FaceLandmarker extends SdkVisionTask<FaceLandmarkerResult> {
  FaceLandmarker._(super.backend, super.runningMode, super.delegate)
    : super(name: 'FaceLandmarker');

  /// Creates a task through the registered official browser adapter.
  static Future<FaceLandmarker> create(FaceLandmarkerOptions options) async {
    await options.prepareModel();
    return FaceLandmarker._(
      await requireBrowserFactory(faceLandmarkerBackendFactory)(options),
      options.runningMode,
      options.delegate,
    );
  }
}
