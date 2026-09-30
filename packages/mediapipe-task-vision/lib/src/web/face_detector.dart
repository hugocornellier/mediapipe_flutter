import '../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Face Detector installed by the web adapter.
///
/// ```dart
/// final task = await FaceDetector.create(
///   FaceDetectorOptions(model: VisionModels.faceDetector),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.detectImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class FaceDetector extends SdkVisionTask<FaceDetectorResult> {
  FaceDetector._(super.backend, super.runningMode, super.delegate)
    : super(name: 'FaceDetector');

  /// Creates a task through the registered official browser adapter.
  static Future<FaceDetector> create(FaceDetectorOptions options) async {
    await options.prepareModel();
    return FaceDetector._(
      await requireBrowserFactory(faceDetectorBackendFactory)(options),
      options.runningMode,
      options.delegate,
    );
  }
}
