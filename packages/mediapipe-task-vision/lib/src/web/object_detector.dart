import '../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Object Detector installed by the web adapter.
///
/// ```dart
/// final task = await ObjectDetector.create(
///   ObjectDetectorOptions(model: VisionModels.objectDetector),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.detectImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class ObjectDetector extends SdkVisionTask<ObjectDetectorResult> {
  ObjectDetector._(super.backend, super.runningMode, super.delegate)
    : super(name: 'ObjectDetector');

  /// Creates a task through the registered official browser adapter.
  static Future<ObjectDetector> create(ObjectDetectorOptions options) async {
    await options.prepareModel();
    return ObjectDetector._(
      await requireBrowserFactory(objectDetectorBackendFactory)(options),
      options.runningMode,
      options.delegate,
    );
  }
}
