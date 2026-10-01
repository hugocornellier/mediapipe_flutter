/// Google's official MediaPipe Audio Classifier: on the shared 1.0.1 runtime
/// natively, and through mediapipe_audio in browsers.
library;

export 'models.dart' show AudioModels;
export 'package:mediapipe_core/capabilities.dart'
    show TaskCapabilities, TaskPlatform;
export 'package:mediapipe_core/mediapipe_exception.dart';
export 'src/audio_types.dart';
// TODO: Move results onto core's shared value types and add a delegate
// option. See tool/API_UNIFICATION.md at the repository root.
export 'src/audio_classifier_web.dart'
    if (dart.library.ffi) 'src/audio_classifier.dart';
export 'src/wav.dart';
