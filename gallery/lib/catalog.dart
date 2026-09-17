import 'package:mediapipe_flutter_vision/capabilities.dart';

/// One entry in the gallery.
///
/// [capabilities] is the package's own support query, so a tile appears only
/// where the runtime is validated. Nothing here restates support by hand: when
/// a task is validated on a new platform the gallery follows automatically.
final class GalleryTask {
  const GalleryTask({
    required this.id,
    required this.title,
    required this.summary,
    required this.model,
    required this.sample,
    required this.capabilities,
    this.live = false,
    String? runtimeId,
  }) : runtimeId = runtimeId ?? id;

  /// Tile id, unique within the catalog.
  final String id;

  /// Task id as the build hook and the bundled manifest spell it. A live demo
  /// shares the runtime of the still-image tile beside it.
  final String runtimeId;
  final String title;
  final String summary;

  /// Whether this tile opens the live camera demo rather than a sample image.
  final bool live;

  /// Model asset name, matching `tool/prepare.py`.
  final String model;

  /// Sample input shipped for the demo.
  final String sample;

  final TaskCapabilities<VisionDelegate> Function(TaskPlatform) capabilities;
}

/// Face tasks have no capability query of their own: they are the baseline
/// every published runtime carries, so support follows the bundled runtime.
TaskCapabilities<VisionDelegate> _faceCapabilities(TaskPlatform platform) =>
    TaskCapabilities.onTargets(
      platform: platform,
      delegates: const {
        VisionDelegate.cpu: {
          'macos/arm64': null,
          'linux/x64': null,
          'windows/x64': null,
          'ios-simulator/arm64': null,
          'android/arm64': null,
          'android/x64': null,
        },
        VisionDelegate.gpu: {'macos/arm64': '14.0'},
      },
      runtimeVersion: '1.0.0',
      unavailableReasons: const {
        VisionDelegate.gpu:
            'Face GPU inference is validated on macOS arm64 14.0+ only.',
      },
    );

/// Live capture needs a camera plugin as well as a runtime. Only macOS is
/// proven here, by the example this demo is lifted from; other platforms get
/// the tile once their camera path is actually exercised.
TaskCapabilities<VisionDelegate> _liveFaceCapabilities(TaskPlatform platform) =>
    TaskCapabilities.onTargets(
      platform: platform,
      delegates: const {
        VisionDelegate.cpu: {'macos/arm64': null},
        VisionDelegate.gpu: {'macos/arm64': '14.0'},
      },
      runtimeVersion: '1.0.0',
      unavailableReasons: const {
        VisionDelegate.cpu:
            'Live camera capture is exercised on macOS arm64 only.',
        VisionDelegate.gpu:
            'Live camera capture is exercised on macOS arm64 only.',
      },
    );

const _catalog = <GalleryTask>[
  GalleryTask(
    id: 'face_detector',
    title: 'Face Detector',
    summary: 'Bounding boxes and six keypoints per face.',
    model: 'blaze_face_short_range.tflite',
    // The short-range model expects a near face; it finds none in the 4K group
    // shot, which is correct behaviour but a poor first impression.
    sample: 'portrait.jpg',
    capabilities: _faceCapabilities,
  ),
  GalleryTask(
    id: 'face_landmarker',
    title: 'Face Landmarker',
    summary: '478 landmarks, 52 blendshapes and a 4x4 transform.',
    model: 'face_landmarker.task',
    sample: 'portrait.jpg',
    capabilities: _faceCapabilities,
  ),
  GalleryTask(
    id: 'face_landmarker_live',
    runtimeId: 'face_landmarker',
    live: true,
    title: 'Live Face Mesh',
    summary: 'Face mesh on the camera feed, with frame timings.',
    model: 'face_landmarker.task',
    sample: 'portrait.jpg',
    capabilities: _liveFaceCapabilities,
  ),
  GalleryTask(
    id: 'object_detector',
    title: 'Object Detector',
    summary: 'Labelled boxes over everyday objects.',
    model: 'efficientdet_lite0.tflite',
    sample: 'group.jpeg',
    capabilities: objectDetectorCapabilitiesForPlatform,
  ),
  GalleryTask(
    id: 'image_classifier',
    title: 'Image Classifier',
    summary: 'Top-k labels with scores.',
    model: 'efficientnet_lite0.tflite',
    sample: 'portrait.jpg',
    capabilities: imageTaskCapabilitiesForPlatform,
  ),
  GalleryTask(
    id: 'image_embedder',
    title: 'Image Embedder',
    summary: 'Feature vectors and cosine similarity.',
    model: 'mobilenet_v3_small.tflite',
    sample: 'portrait.jpg',
    capabilities: imageTaskCapabilitiesForPlatform,
  ),
  GalleryTask(
    id: 'hand_landmarker',
    title: 'Hand Landmarker',
    summary: '21 landmarks per hand, with handedness.',
    model: 'hand_landmarker.task',
    sample: 'hands.jpg',
    capabilities: landmarkTaskCapabilitiesForPlatform,
  ),
  GalleryTask(
    id: 'gesture_recognizer',
    title: 'Gesture Recognizer',
    summary: 'Hand landmarks plus a recognised gesture.',
    model: 'gesture_recognizer.task',
    sample: 'thumb_up.jpg',
    capabilities: landmarkTaskCapabilitiesForPlatform,
  ),
  GalleryTask(
    id: 'pose_landmarker',
    title: 'Pose Landmarker',
    summary: '33 body landmarks with visibility.',
    model: 'pose_landmarker_lite.task',
    sample: 'pose.jpg',
    capabilities: landmarkTaskCapabilitiesForPlatform,
  ),
  GalleryTask(
    id: 'holistic_landmarker',
    title: 'Holistic Landmarker',
    summary: 'Face, hands and pose in one graph.',
    model: 'holistic_landmarker.task',
    sample: 'pose.jpg',
    capabilities: landmarkTaskCapabilitiesForPlatform,
  ),
  GalleryTask(
    id: 'image_segmenter',
    title: 'Image Segmenter',
    summary: 'Category and confidence masks.',
    model: 'deeplab_v3.tflite',
    sample: 'portrait.jpg',
    capabilities: segmenterTaskCapabilitiesForPlatform,
  ),
  GalleryTask(
    id: 'interactive_segmenter_legacy',
    title: 'Interactive Segmenter',
    summary: 'MagicTouch segmentation from a point or box.',
    model: 'magic_touch.tflite',
    sample: 'portrait.jpg',
    capabilities: interactiveSegmenterCapabilitiesForPlatform,
  ),
];

/// The catalog restricted to tasks this build actually bundled and whose
/// runtime is validated here. [bundled] comes from `assets/manifest.json`.
List<GalleryTask> supportedTasks(TaskPlatform platform, Set<String> bundled) => [
  for (final task in _catalog)
    if (bundled.contains(task.runtimeId) &&
        task.capabilities(platform).isSupported)
      task,
];

/// Tasks bundled by this build whose runtime is not validated here, with the
/// package's own reason. Shown only in the about sheet, never as a tile.
Map<GalleryTask, String> unvalidatedTasks(
  TaskPlatform platform,
  Set<String> bundled,
) => {
  for (final task in _catalog)
    if (bundled.contains(task.runtimeId) &&
        !task.capabilities(platform).isSupported)
      task: task.capabilities(platform).unavailableReasons.values.firstOrNull ??
          'Not validated on this platform.',
};
