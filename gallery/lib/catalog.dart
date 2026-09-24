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

  /// A text task on typed input.
  text,

  /// An audio task on a clip.
  audio,
}

/// The home page's sections, in MediaPipe Studio's order.
enum GalleryCategory {
  vision('Vision'),
  audio('Audio'),
  text('Text');

  const GalleryCategory(this.title);
  final String title;
}

/// A MediaPipe task the home page lists in its section on every platform
/// even though the gallery cannot run it yet, with the reason it cannot.
typedef PlannedTask = ({
  GalleryCategory category,
  String title,
  String summary,
  String reason,
});

/// Audio and text tasks, listed as MediaPipe Studio lists them. Their
/// packages run them on macOS arm64; elsewhere their cards say so.
const plannedTasks = <PlannedTask>[
  (
    category: GalleryCategory.audio,
    title: 'Audio Classifier',
    summary: 'Sound categories in a clip or the microphone.',
    reason: 'The audio package runs this on macOS arm64 only.',
  ),
  (
    category: GalleryCategory.text,
    title: 'Language Detector',
    summary: 'The language of a piece of text.',
    reason: 'The text package runs this on macOS arm64 only.',
  ),
  (
    category: GalleryCategory.text,
    title: 'Text Classifier',
    summary: 'Sentiment and categories of a piece of text.',
    reason: 'The text package runs this on macOS arm64 only.',
  ),
  (
    category: GalleryCategory.text,
    title: 'Text Embedder',
    summary: 'Text as a vector, compared by similarity.',
    reason: 'The text package runs this on macOS arm64 only.',
  ),
];

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
    this.officialMacosCapabilities,
    this.category = GalleryCategory.vision,
    String? runtimeId,
  }) : runtimeId = runtimeId ?? id;

  /// The home page section the tile belongs to.
  final GalleryCategory category;

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

  /// The capability claim this entry earns when the build manifest says the
  /// official macOS landmark runtime was selected for [runtimeId], if any.
  final TaskCapabilities<VisionDelegate> Function(TaskPlatform)?
  officialMacosCapabilities;

  bool get isExperimental => experimentalReason != null;

  /// Model asset name, matching `tool/prepare.py`.
  final String model;

  /// Sample input shipped for the demo.
  final String sample;

  final TaskCapabilities<VisionDelegate> Function(TaskPlatform) capabilities;

  TaskCapabilities<VisionDelegate> capabilitiesFor(
    TaskPlatform platform,
    Set<String> officialMacosLandmarkTasks,
  ) => switch (officialMacosCapabilities) {
    final official? when officialMacosLandmarkTasks.contains(runtimeId) =>
      official(platform),
    _ => capabilities(platform),
  };
}

// tool/prepare.py builds every iOS target against Google's official SDK, so
// Hand Landmarker always has the package's official iOS adapter there.
TaskCapabilities<VisionDelegate> _hand(TaskPlatform platform) =>
    handLandmarkerCapabilitiesForPlatform(platform, officialIosRuntime: true);

TaskCapabilities<VisionDelegate> _officialMacosHand(TaskPlatform platform) =>
    handLandmarkerCapabilitiesForPlatform(
      platform,
      officialMacosRuntime: true,
      officialIosRuntime: true,
    );

TaskCapabilities<VisionDelegate> _pose(TaskPlatform platform) =>
    poseLandmarkerCapabilitiesForPlatform(platform, officialIosRuntime: true);

TaskCapabilities<VisionDelegate> _officialMacosPose(TaskPlatform platform) =>
    poseLandmarkerCapabilitiesForPlatform(
      platform,
      officialMacosRuntime: true,
      officialIosRuntime: true,
    );

TaskCapabilities<VisionDelegate> _objects(TaskPlatform platform) =>
    objectDetectorCapabilitiesForPlatform(platform, officialIosRuntime: true);

TaskCapabilities<VisionDelegate> _classifier(TaskPlatform platform) =>
    imageClassifierCapabilitiesForPlatform(platform, officialIosRuntime: true);

TaskCapabilities<VisionDelegate> _officialMacosObjects(TaskPlatform platform) =>
    objectDetectorCapabilitiesForPlatform(
      platform,
      officialMacosRuntime: true,
      officialIosRuntime: true,
    );

TaskCapabilities<VisionDelegate> _officialMacosClassifier(
  TaskPlatform platform,
) => imageClassifierCapabilitiesForPlatform(
  platform,
  officialMacosRuntime: true,
  officialIosRuntime: true,
);

TaskCapabilities<VisionDelegate> _embedder(TaskPlatform platform) =>
    imageEmbedderCapabilitiesForPlatform(platform, officialIosRuntime: true);

TaskCapabilities<VisionDelegate> _officialMacosEmbedder(
  TaskPlatform platform,
) => imageEmbedderCapabilitiesForPlatform(
  platform,
  officialMacosRuntime: true,
  officialIosRuntime: true,
);

TaskCapabilities<VisionDelegate> _segmenter(TaskPlatform platform) =>
    imageSegmenterCapabilitiesForPlatform(platform, officialIosRuntime: true);

TaskCapabilities<VisionDelegate> _officialMacosSegmenter(
  TaskPlatform platform,
) => imageSegmenterCapabilitiesForPlatform(
  platform,
  officialMacosRuntime: true,
  officialIosRuntime: true,
);

TaskCapabilities<VisionDelegate> _officialMacosLegacySegmenter(
  TaskPlatform platform,
) => interactiveSegmenterLegacyCapabilitiesForPlatform(
  platform,
  officialMacosRuntime: true,
  officialIosRuntime: true,
);

TaskCapabilities<VisionDelegate> _magicTouch(TaskPlatform platform) =>
    interactiveSegmenterCapabilitiesForPlatform(
      platform,
      officialIosRuntime: true,
    );

TaskCapabilities<VisionDelegate> _legacySegmenter(TaskPlatform platform) =>
    interactiveSegmenterLegacyCapabilitiesForPlatform(
      platform,
      officialIosRuntime: true,
    );

TaskCapabilities<VisionDelegate> _gesture(TaskPlatform platform) =>
    gestureRecognizerCapabilitiesForPlatform(
      platform,
      officialIosRuntime: true,
    );

TaskCapabilities<VisionDelegate> _holistic(TaskPlatform platform) =>
    holisticLandmarkerCapabilitiesForPlatform(
      platform,
      officialIosRuntime: true,
    );

TaskCapabilities<VisionDelegate> _officialMacosGesture(TaskPlatform platform) =>
    gestureRecognizerCapabilitiesForPlatform(
      platform,
      officialMacosRuntime: true,
      officialIosRuntime: true,
    );

TaskCapabilities<VisionDelegate> _officialMacosHolistic(
  TaskPlatform platform,
) => holisticLandmarkerCapabilitiesForPlatform(
  platform,
  officialMacosRuntime: true,
  officialIosRuntime: true,
);

/// The audio and text tasks' support: CPU on core's shared 1.0.1 runtime.
TaskCapabilities<VisionDelegate> _text(TaskPlatform platform) =>
    TaskCapabilities.cpuOnTargets(
      platform: platform,
      cpu: VisionDelegate.cpu,
      gpu: VisionDelegate.gpu,
      gpuUnavailableReason:
          'The official 1.0.1 audio and text tasks run on CPU here.',
    );

final _catalog = <GalleryTask>[
  GalleryTask(
    id: 'face_landmarker_live',
    runtimeId: 'face_landmarker',
    demo: GalleryDemo.live,
    title: 'Live Face Landmarker',
    summary: 'Facial landmarks on the camera feed, with frame timings.',
    model: 'face_landmarker.task',
    sample: 'portrait.jpg',
    capabilities: faceLandmarkerCapabilitiesForPlatform,
  ),
  GalleryTask(
    id: 'hand_landmarker_live',
    runtimeId: 'hand_landmarker',
    demo: GalleryDemo.live,
    title: 'Live Hand Landmarker',
    summary: 'Hand landmarks and handedness on the camera feed.',
    model: 'hand_landmarker.task',
    sample: 'hands.jpg',
    capabilities: _hand,
    officialMacosCapabilities: _officialMacosHand,
  ),
  GalleryTask(
    id: 'pose_landmarker_live',
    runtimeId: 'pose_landmarker',
    demo: GalleryDemo.live,
    title: 'Live Pose Landmarker',
    summary: 'Pose landmarks and skeleton on the camera feed.',
    model: 'pose_landmarker_lite.task',
    sample: 'pose.jpg',
    capabilities: _pose,
    officialMacosCapabilities: _officialMacosPose,
  ),
  GalleryTask(
    id: 'gesture_recognizer_live',
    runtimeId: 'gesture_recognizer',
    demo: GalleryDemo.live,
    title: 'Live Gesture Recognizer',
    summary: 'Hand landmarks and the recognised gesture on the camera feed.',
    model: 'gesture_recognizer.task',
    sample: 'thumb_up.jpg',
    capabilities: _gesture,
    officialMacosCapabilities: _officialMacosGesture,
  ),
  GalleryTask(
    id: 'holistic_landmarker_live',
    runtimeId: 'holistic_landmarker',
    demo: GalleryDemo.live,
    title: 'Live Holistic Landmarker',
    summary: 'Body, hands and face together on the camera feed.',
    model: 'holistic_landmarker.task',
    sample: 'pose.jpg',
    capabilities: _holistic,
    officialMacosCapabilities: _officialMacosHolistic,
  ),
  GalleryTask(
    id: 'face_detector_live',
    runtimeId: 'face_detector',
    demo: GalleryDemo.live,
    title: 'Live Face Detector',
    summary: 'Face boxes and six keypoints on the camera feed.',
    model: 'blaze_face_short_range.tflite',
    sample: 'portrait.jpg',
    capabilities: faceDetectorCapabilitiesForPlatform,
  ),
  GalleryTask(
    id: 'object_detector_live',
    runtimeId: 'object_detector',
    demo: GalleryDemo.live,
    title: 'Live Object Detector',
    summary: 'Labelled boxes over everyday objects on the camera feed.',
    model: 'efficientdet_lite0.tflite',
    sample: 'group.jpeg',
    capabilities: _objects,
    officialMacosCapabilities: _officialMacosObjects,
  ),
  GalleryTask(
    id: 'image_classifier_live',
    runtimeId: 'image_classifier',
    demo: GalleryDemo.live,
    title: 'Live Image Classifier',
    summary: 'The top three classes for the camera feed.',
    model: 'efficientnet_lite0.tflite',
    sample: 'portrait.jpg',
    capabilities: _classifier,
    officialMacosCapabilities: _officialMacosClassifier,
  ),
  GalleryTask(
    id: 'image_embedder_live',
    runtimeId: 'image_embedder',
    demo: GalleryDemo.live,
    title: 'Live Image Embedder',
    summary: 'How similar each frame is to the first, from feature vectors.',
    model: 'mobilenet_v3_small.tflite',
    sample: 'portrait.jpg',
    capabilities: _embedder,
    officialMacosCapabilities: _officialMacosEmbedder,
  ),
  GalleryTask(
    id: 'object_detector',
    title: 'Object Detector',
    summary: 'Labelled boxes over everyday objects.',
    model: 'efficientdet_lite0.tflite',
    sample: 'group.jpeg',
    capabilities: _objects,
    officialMacosCapabilities: _officialMacosObjects,
  ),
  GalleryTask(
    id: 'image_classifier',
    title: 'Image Classifier',
    summary: 'Top-k labels with scores.',
    model: 'efficientnet_lite0.tflite',
    sample: 'portrait.jpg',
    capabilities: _classifier,
    officialMacosCapabilities: _officialMacosClassifier,
  ),
  GalleryTask(
    id: 'image_embedder',
    title: 'Image Embedder',
    summary: 'Feature vectors and cosine similarity.',
    model: 'mobilenet_v3_small.tflite',
    sample: 'portrait.jpg',
    capabilities: _embedder,
    officialMacosCapabilities: _officialMacosEmbedder,
  ),
  GalleryTask(
    id: 'hand_landmarker',
    title: 'Hand Landmarker',
    summary: '21 landmarks per hand, with handedness.',
    model: 'hand_landmarker.task',
    sample: 'hands.jpg',
    capabilities: _hand,
    officialMacosCapabilities: _officialMacosHand,
  ),
  GalleryTask(
    id: 'gesture_recognizer',
    title: 'Gesture Recognizer',
    summary: 'Hand landmarks plus a recognised gesture.',
    model: 'gesture_recognizer.task',
    sample: 'thumb_up.jpg',
    capabilities: _gesture,
    officialMacosCapabilities: _officialMacosGesture,
  ),
  GalleryTask(
    id: 'pose_landmarker',
    title: 'Pose Landmarker',
    summary: '33 body landmarks with visibility.',
    model: 'pose_landmarker_lite.task',
    sample: 'pose.jpg',
    capabilities: _pose,
    officialMacosCapabilities: _officialMacosPose,
  ),
  GalleryTask(
    id: 'holistic_landmarker',
    title: 'Holistic Landmarker',
    summary: 'Face, hands and pose in one graph.',
    model: 'holistic_landmarker.task',
    sample: 'pose.jpg',
    capabilities: _holistic,
    officialMacosCapabilities: _officialMacosHolistic,
  ),
  GalleryTask(
    id: 'image_segmenter',
    title: 'Image Segmenter',
    summary: 'Category and confidence masks.',
    model: 'deeplab_v3.tflite',
    sample: 'portrait.jpg',
    capabilities: _segmenter,
    officialMacosCapabilities: _officialMacosSegmenter,
  ),
  GalleryTask(
    id: 'image_segmenter_live',
    runtimeId: 'image_segmenter',
    demo: GalleryDemo.live,
    title: 'Live Image Segmenter',
    summary: 'People and objects masked in each camera frame.',
    model: 'deeplab_v3.tflite',
    sample: 'portrait.jpg',
    capabilities: _segmenter,
    officialMacosCapabilities: _officialMacosSegmenter,
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
    capabilities: _legacySegmenter,
    officialMacosCapabilities: _officialMacosLegacySegmenter,
  ),
  GalleryTask(
    id: 'interactive_segmenter',
    demo: GalleryDemo.segment,
    title: 'MagicTouch',
    summary: 'Tap a subject to segment it, stroke by stroke.',
    model: 'interactive_segmentation.task',
    sample: 'animals.jpg',
    capabilities: _magicTouch,
  ),
  // The audio package's Audio Classifier, on the same shared runtime.
  GalleryTask(
    id: 'audio_classifier',
    category: GalleryCategory.audio,
    demo: GalleryDemo.audio,
    title: 'Audio Classifier',
    summary: 'Sound categories in a clip, second by second.',
    model: 'yamnet.tflite',
    sample: 'speech_16000_hz_mono.wav',
    capabilities: _text,
  ),
  // The text package's classic tasks, on the shared 1.0.1 runtime: macOS
  // arm64 CPU, where prepare.py bundles their models.
  GalleryTask(
    id: 'language_detector',
    category: GalleryCategory.text,
    demo: GalleryDemo.text,
    title: 'Language Detector',
    summary: 'The language of a piece of text.',
    model: 'language_detector.tflite',
    sample: '',
    capabilities: _text,
  ),
  GalleryTask(
    id: 'text_classifier',
    category: GalleryCategory.text,
    demo: GalleryDemo.text,
    title: 'Text Classifier',
    summary: 'Sentiment of a piece of text.',
    model: 'bert_classifier.tflite',
    sample: '',
    capabilities: _text,
  ),
  GalleryTask(
    id: 'text_embedder',
    category: GalleryCategory.text,
    demo: GalleryDemo.text,
    title: 'Text Embedder',
    summary: 'Two texts as vectors, compared by similarity.',
    model: 'universal_sentence_encoder.tflite',
    sample: '',
    capabilities: _text,
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
