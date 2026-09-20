import 'live_registry.dart';
import 'live_tasks_native.dart';

/// Native-only demos retain their existing task and shared painter.
Map<String, LiveDemo> additionalLiveDemos(dynamic painter) => {
  'hand_landmarker_live': (task: HandLandmarkerLiveTask.new, overlay: painter),
  'pose_landmarker_live': (task: PoseLandmarkerLiveTask.new, overlay: painter),
};
