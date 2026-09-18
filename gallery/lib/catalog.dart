import 'package:mediapipe_flutter_vision/capabilities.dart';

/// How a tile demonstrates its task.
enum GalleryDemo {
  /// Known to the gallery and reported in the about sheet, but with no screen
  /// of its own, so it never becomes a tile.
  none,

  /// Live camera capture.
  live,

  /// Interactive segmentation on a bundled image.
  segment,
}

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
    this.demo = GalleryDemo.none,
    this.experimentalReason,
    this.officialMacosLandmarkTask = false,
    String? runtimeId,
  }) : runtimeId = runtimeId ?? id;

  /// Tile id, unique within the catalog.
  final String id;

  /// Task id as the build hook and the bundled manifest spell it. A live demo
  /// shares the runtime of the still-image tile beside it.
  final String runtimeId;
  final String title;
  final String summary;

  /// How this tile demonstrates its task.
  final GalleryDemo demo;

  /// Whether this tile opens the live camera demo.
  bool get live => demo == GalleryDemo.live;

  /// Whether this entry has a screen of its own, and so can be a tile.
  bool get hasOwnPage => demo != GalleryDemo.none;

  /// Why this tile's task is not validated on the platforms it appears on.
  ///
  /// A tile with a reason runs real inference but has never been checked
  /// against Google's outputs here, so it is shown apart from the validated
  /// ones and never counted among them.
  final String? experimentalReason;

  /// Whether this entry has an earned capability claim when the build manifest
  /// says the official macOS landmark runtime was selected for [runtimeId].
  final bool officialMacosLandmarkTask;

  bool get isExperimental => experimentalReason != null;

  /// Model asset name, matching `tool/prepare.py`.
  final String model;

  /// Sample input shipped for the demo.
  final String sample;

  final TaskCapabilities<VisionDelegate> Function(TaskPlatform) capabilities;

  TaskCapabilities<VisionDelegate> capabilitiesFor(
    TaskPlatform platform,
    Set<String> officialMacosLandmarkTasks,
  ) =>
      officialMacosLandmarkTask &&
          officialMacosLandmarkTasks.contains(runtimeId)
      ? landmarkTaskCapabilitiesForPlatform(
          platform,
          officialMacosRuntime: true,
        )
      : capabilities(platform);
}

final _catalog = <GalleryTask>[
  GalleryTask(
    id: 'face_landmarker_live',
    runtimeId: 'face_landmarker',
    demo: GalleryDemo.live,
    title: 'Live Face Mesh',
    summary: 'Face mesh on the camera feed, with frame timings.',
    model: 'face_landmarker.task',
    sample: 'portrait.jpg',
    capabilities: faceLandmarkerCapabilitiesForPlatform,
  ),
  GalleryTask(
    id: 'hand_landmarker_live',
    runtimeId: 'hand_landmarker',
    demo: GalleryDemo.live,
    title: 'Live Hands',
    summary: 'Hand landmarks and handedness on the camera feed.',
    model: 'hand_landmarker.task',
    sample: 'hands.jpg',
    capabilities: landmarkTaskCapabilitiesForPlatform,
    officialMacosLandmarkTask: true,
  ),
  GalleryTask(
    id: 'pose_landmarker_live',
    runtimeId: 'pose_landmarker',
    demo: GalleryDemo.live,
    title: 'Live Pose',
    summary: 'Pose landmarks and skeleton on the camera feed.',
    model: 'pose_landmarker_lite.task',
    sample: 'pose.jpg',
    capabilities: landmarkTaskCapabilitiesForPlatform,
    officialMacosLandmarkTask: true,
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
    officialMacosLandmarkTask: true,
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
    officialMacosLandmarkTask: true,
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
  // Two different implementations share the MagicTouch name. This is the
  // stateless legacy API inside the combined vision runtime; the stateful
  // InteractiveSegmenter below is a separate 1.0.1 runtime with its own
  // support table. Their capability queries are not interchangeable.
  GalleryTask(
    id: 'interactive_segmenter_legacy',
    title: 'Interactive Segmenter (legacy)',
    summary: 'Stateless MagicTouch segmentation from a point or box.',
    model: 'magic_touch.tflite',
    sample: 'portrait.jpg',
    capabilities: segmenterTaskCapabilitiesForPlatform,
  ),
  GalleryTask(
    id: 'interactive_segmenter',
    demo: GalleryDemo.segment,
    title: 'MagicTouch',
    summary: 'Tap a subject to segment it, stroke by stroke.',
    model: 'interactive_segmentation.task',
    sample: 'animals.jpg',
    capabilities: interactiveSegmenterCapabilitiesForPlatform,
  ),
];

/// The catalog restricted to tasks this build actually bundled and whose
/// runtime is validated here. [bundled] comes from `assets/manifest.json`.
List<GalleryTask> supportedTasks(
  TaskPlatform platform,
  Set<String> bundled,
  Set<String> officialMacosLandmarkTasks,
) => [
  for (final task in _catalog)
    if (bundled.contains(task.runtimeId) &&
        task.capabilitiesFor(platform, officialMacosLandmarkTasks).isSupported)
      task,
];

/// Tasks bundled by this build whose runtime is not validated here, with the
/// package's own reason. Shown only in the about sheet, never as a tile.
Map<GalleryTask, String> unvalidatedTasks(
  TaskPlatform platform,
  Set<String> bundled,
  Set<String> officialMacosLandmarkTasks,
) => {
  for (final task in _catalog)
    if (bundled.contains(task.runtimeId) &&
        !task.capabilitiesFor(platform, officialMacosLandmarkTasks).isSupported)
      task:
          task
              .capabilitiesFor(platform, officialMacosLandmarkTasks)
              .unavailableReasons
              .values
              .firstOrNull ??
          'Not validated on this platform.',
};
