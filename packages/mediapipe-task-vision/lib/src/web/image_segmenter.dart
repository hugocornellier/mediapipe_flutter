import '../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Image Segmenter installed by the web adapter.
///
/// ```dart
/// final task = await ImageSegmenter.create(
///   ImageSegmenterOptions(model: VisionModels.imageSegmenter),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.segmentImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class ImageSegmenter extends SdkVisionTask<SegmentationResult> {
  ImageSegmenter._(super.backend, super.runningMode, super.delegate)
    : super(name: 'ImageSegmenter');

  /// Creates a task through the registered official browser adapter.
  static Future<ImageSegmenter> create(ImageSegmenterOptions options) async {
    await options.prepareModel();
    return ImageSegmenter._(
      await requireBrowserFactory(imageSegmenterBackendFactory)(options),
      options.runningMode,
      options.delegate,
    );
  }

  /// Segments a still image, as on native platforms.
  Future<SegmentationResult> segmentImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) => detectImage(image, rotationDegrees: rotationDegrees);

  /// Segments a video frame, as on native platforms.
  Future<SegmentationResult> segmentForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) => detectForVideo(
    image,
    timestampMilliseconds: timestampMilliseconds,
    rotationDegrees: rotationDegrees,
  );
}
