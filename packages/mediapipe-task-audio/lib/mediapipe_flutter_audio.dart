/// Google's official MediaPipe Audio Classifier: on the shared 1.0.1 runtime
/// natively, and through mediapipe_flutter_audio_web in browsers.
library;

export 'src/audio_types.dart';
export 'src/audio_classifier_web.dart'
    if (dart.library.ffi) 'src/audio_classifier.dart';
export 'src/wav.dart';
