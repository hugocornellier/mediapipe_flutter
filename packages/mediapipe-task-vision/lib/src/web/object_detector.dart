import '../../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Object Detector installed by the web adapter.
final class ObjectDetector extends SdkVisionTask<ObjectDetectorResult> {
  ObjectDetector._(super.backend, super.runningMode, super.delegate)
    : super(name: 'ObjectDetector');

  /// Creates a task through the registered official browser adapter.
  static Future<ObjectDetector> create(ObjectDetectorOptions options) async =>
      ObjectDetector._(
        await requireBrowserFactory(objectDetectorBackendFactory)(options),
        options.runningMode,
        options.delegate,
      );
}
