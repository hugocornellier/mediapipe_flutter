import '../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Interactive Segmenter Legacy installed by the
/// web adapter: the stateless MagicTouch API, selecting the object under a
/// point.
///
/// ```dart
/// final task = await InteractiveSegmenterLegacy.create(
///   InteractiveSegmenterLegacyOptions(model: VisionModels.interactiveSegmenterLegacy),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.segmentImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class InteractiveSegmenterLegacy
    extends SdkVisionTask<SegmentationResult> {
  InteractiveSegmenterLegacy._(super.backend, super.runningMode, super.delegate)
    : super(name: 'InteractiveSegmenterLegacy');

  /// Creates a task through the registered official browser adapter.
  static Future<InteractiveSegmenterLegacy> create(
    InteractiveSegmenterLegacyOptions options,
  ) async {
    await options.prepareModel();
    return InteractiveSegmenterLegacy._(
      await requireBrowserFactory(interactiveSegmenterLegacyBackendFactory)(
        options,
      ),
      RunningMode.image,
      options.delegate,
    );
  }

  /// Segments the object under [keypoint], as on native platforms.
  Future<SegmentationResult> segmentImage(
    VisionImage image, {
    required SegmentationPoint keypoint,
    int rotationDegrees = 0,
  }) =>
      detectImage(image, rotationDegrees: rotationDegrees, keypoint: keypoint);
}
