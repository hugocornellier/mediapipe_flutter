import '../../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Gesture Recognizer installed by the web adapter.
final class GestureRecognizer extends SdkVisionTask<GestureRecognizerResult> {
  GestureRecognizer._(super.backend, super.runningMode, super.delegate)
    : super(name: 'GestureRecognizer');

  /// Creates a task through the registered official browser adapter.
  static Future<GestureRecognizer> create(
    GestureRecognizerOptions options,
  ) async => GestureRecognizer._(
    await requireBrowserFactory(gestureRecognizerBackendFactory)(options),
    options.runningMode,
    options.delegate,
  );

  /// Recognizes gestures in one still image, as on native platforms.
  Future<GestureRecognizerResult> recognizeImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) => detectImage(image, rotationDegrees: rotationDegrees);

  /// Recognizes gestures in a video frame, as on native platforms.
  Future<GestureRecognizerResult> recognizeForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) => detectForVideo(
    image,
    timestampMilliseconds: timestampMilliseconds,
    rotationDegrees: rotationDegrees,
  );
}
