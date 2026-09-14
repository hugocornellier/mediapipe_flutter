/// Query modern interactive segmentation support without loading a model.
library;

import 'package:mediapipe_flutter_core/capabilities.dart';
import 'src/interface/vision_types.dart';

export 'package:mediapipe_flutter_core/capabilities.dart'
    show TaskCapabilities, TaskPlatform;
export 'src/interface/vision_types.dart' show VisionDelegate;

/// Describe the package's stateful MagicTouch support on this process platform.
Future<TaskCapabilities<VisionDelegate>>
queryInteractiveSegmenterCapabilities() async =>
    interactiveSegmenterCapabilitiesForPlatform(await currentTaskPlatform());

/// Evaluate support for an explicit process platform snapshot.
TaskCapabilities<VisionDelegate> interactiveSegmenterCapabilitiesForPlatform(
  TaskPlatform platform,
) => TaskCapabilities.macosCpu(
  platform: platform,
  cpu: VisionDelegate.cpu,
  gpu: VisionDelegate.gpu,
  gpuUnavailableReason:
      'The official MediaPipe 1.0.1 macOS GPU stroke shader requests GLSL 330 '
      'in an OpenGL 2.1 context and fails to compile. CPU is supported.',
);
