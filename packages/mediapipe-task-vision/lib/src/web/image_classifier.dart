import '../../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Image Classifier installed by the web adapter.
final class ImageClassifier extends SdkVisionTask<ImageClassifierResult> {
  ImageClassifier._(super.backend, super.runningMode, super.delegate)
    : super(name: 'ImageClassifier');

  /// Creates a task through the registered official browser adapter.
  static Future<ImageClassifier> create(ImageClassifierOptions options) async =>
      ImageClassifier._(
        await requireBrowserFactory(imageClassifierBackendFactory)(options),
        options.runningMode,
        options.delegate,
      );

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
