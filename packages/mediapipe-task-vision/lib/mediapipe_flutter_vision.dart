/// Official MediaPipe vision tasks with platform-specific implementations.
library;

export 'vision_native.dart' if (dart.library.js_interop) 'src/web/vision.dart';
