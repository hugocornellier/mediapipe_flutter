/// Query per-task delegate support without loading a model.
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
      'The official MediaPipe macOS GPU stroke shader requests GLSL 330 in an '
      'OpenGL 2.1 context and fails to compile. Confirmed on both the 1.0.0 and '
      '1.0.1 official runtimes, so it is not fixed by changing version. Metal '
      'itself is fine; only GL-shader calculators are affected. This task '
      'supports CPU only.',
);

/// Describe the package's Object Detector support on this process platform.
Future<TaskCapabilities<VisionDelegate>>
queryObjectDetectorCapabilities() async =>
    objectDetectorCapabilitiesForPlatform(await currentTaskPlatform());

/// Evaluate support for an explicit process platform snapshot.
///
/// This task is the inverse of MagicTouch: Metal is validated against the
/// official reference and CPU is the broken path.
TaskCapabilities<VisionDelegate> objectDetectorCapabilitiesForPlatform(
  TaskPlatform platform,
) => TaskCapabilities.gpuOnTargets(
  platform: platform,
  cpu: VisionDelegate.cpu,
  gpu: VisionDelegate.gpu,
  runtimeVersion: '1.0.0',
  cpuUnavailableReason:
      'CPU inference aborts with SIGILL inside XNNPACK\'s KleidiAI SME kernels '
      'in the pinned v1.0.0 source build. This task supports Metal only; see '
      'tool/OBJECT_DETECTOR.md.',
);
