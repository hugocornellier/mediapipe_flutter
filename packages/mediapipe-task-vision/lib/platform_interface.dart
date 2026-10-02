/// Where the Android and browser plugins plug Google's SDKs into the vision
/// task classes: the backend interfaces and factories, and the one decoder
/// both adapters deliver results through.
///
/// Applications should import `mediapipe_vision.dart` instead.
library;

export 'package:mediapipe_core/platform_interface.dart'
    show taskPlatformGpuReader;

export 'src/results/decoders.dart';
export 'src/results/landmark_codec.dart';
export 'src/vision_task_backend.dart';
