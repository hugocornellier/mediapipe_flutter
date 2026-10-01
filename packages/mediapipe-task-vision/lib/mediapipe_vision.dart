/// Official MediaPipe vision tasks with platform-specific implementations.
library;

export 'models.dart' show VisionModels;
export 'package:mediapipe_core/mediapipe_exception.dart';
// TODO: Give every platform the same task classes; web's differ from native's
// today. See tool/API_UNIFICATION.md at the repository root.
export 'vision_native.dart' if (dart.library.js_interop) 'src/web/vision.dart';
