import '../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Image Classifier installed by the web adapter.
///
/// ```dart
/// final task = await ImageClassifier.create(
///   ImageClassifierOptions(model: VisionModels.imageClassifier),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.classifyImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class ImageClassifier extends SdkVisionTask<ImageClassifierResult> {
  ImageClassifier._(super.backend, super.runningMode, super.delegate)
    : super(name: 'ImageClassifier');

  /// Creates a task through the registered official browser adapter.
  static Future<ImageClassifier> create(ImageClassifierOptions options) async {
    await options.prepareModel();
    return ImageClassifier._(
      await requireBrowserFactory(imageClassifierBackendFactory)(options),
      options.runningMode,
      options.delegate,
    );
  }

  /// Classifies a still image or a normalized region, as on native platforms.
  Future<ImageClassifierResult> classifyImage(
    VisionImage image, {
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
  }) => detectImage(
    image,
    rotationDegrees: rotationDegrees,
    regionOfInterest: regionOfInterest,
  );

  /// Classifies a video frame, as on native platforms.
  Future<ImageClassifierResult> classifyForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
  }) => detectForVideo(
    image,
    timestampMilliseconds: timestampMilliseconds,
    rotationDegrees: rotationDegrees,
    regionOfInterest: regionOfInterest,
  );
}
