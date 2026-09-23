import 'live_registry.dart';
import 'live_tasks_native.dart';

/// Native-only demos retain their existing task and shared painter.
Map<String, LiveDemo> additionalLiveDemos(dynamic painter) => {
  'hand_landmarker_live': (task: HandLandmarkerLiveTask.new, overlay: painter),
  'pose_landmarker_live': (task: PoseLandmarkerLiveTask.new, overlay: painter),
  'gesture_recognizer_live': (
    task: GestureRecognizerLiveTask.new,
    overlay: painter,
  ),
  'holistic_landmarker_live': (
    task: HolisticLandmarkerLiveTask.new,
    overlay: painter,
  ),
  'face_detector_live': (task: FaceDetectorLiveTask.new, overlay: painter),
  'object_detector_live': (task: ObjectDetectorLiveTask.new, overlay: painter),
  'image_classifier_live': (
    task: ImageClassifierLiveTask.new,
    overlay: painter,
  ),
  'image_embedder_live': (task: ImageEmbedderLiveTask.new, overlay: painter),
  'image_segmenter_live': (task: ImageSegmenterLiveTask.new, overlay: painter),
};
