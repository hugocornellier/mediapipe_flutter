import '../web/live_tasks.dart';
import 'live_registry.dart';

/// Browser demos beyond Face Landmarker, drawn by the shared landmark painter.
Map<String, LiveDemo> additionalLiveDemos(dynamic painter) => {
  'hand_landmarker_live': (task: HandLandmarkerLiveTask.new, overlay: painter),
};
