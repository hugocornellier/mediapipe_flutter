import '../../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Interactive Segmenter Legacy installed by the
/// web adapter: the stateless MagicTouch API, selecting the object under a
/// point.
final class InteractiveSegmenterLegacy
    extends SdkVisionTask<SegmentationResult> {
  InteractiveSegmenterLegacy._(super.backend, super.runningMode, super.delegate)
    : super(name: 'InteractiveSegmenterLegacy');

  /// Creates a task through the registered official browser adapter.
  static Future<InteractiveSegmenterLegacy> create(
    InteractiveSegmenterLegacyOptions options,
  ) async => InteractiveSegmenterLegacy._(
    await requireBrowserFactory(interactiveSegmenterLegacyBackendFactory)(
      options,
    ),
    VisionRunningMode.image,
    options.delegate,
  );

  /// Segments the object under [keypoint], as on native platforms.
  Future<SegmentationResult> segmentImage(
    VisionImage image, {
    required SegmentationPoint keypoint,
    int rotationDegrees = 0,
  }) =>
      detectImage(image, rotationDegrees: rotationDegrees, keypoint: keypoint);
}
