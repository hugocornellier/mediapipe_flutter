/// Shared APIs for MediaPipe package implementations and platform plugins.
///
/// Applications should import `mediapipe_core.dart` instead.
library;

export 'src/model_source.dart';
export 'src/model_source_io.dart'
    if (dart.library.js_interop) 'src/model_source_web.dart';
