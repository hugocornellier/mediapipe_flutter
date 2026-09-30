import '../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Gesture Recognizer installed by the web adapter.
///
/// ```dart
/// final task = await GestureRecognizer.create(
///   GestureRecognizerOptions(model: VisionModels.gestureRecognizer),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.recognizeImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class GestureRecognizer extends SdkVisionTask<GestureRecognizerResult> {
  GestureRecognizer._(super.backend, super.runningMode, super.delegate)
    : super(name: 'GestureRecognizer');

  /// Creates a task through the registered official browser adapter.
  static Future<GestureRecognizer> create(
    GestureRecognizerOptions options,
  ) async {
    await options.prepareModel();
    return GestureRecognizer._(
      await requireBrowserFactory(gestureRecognizerBackendFactory)(options),
      options.runningMode,
      options.delegate,
    );
  }

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
