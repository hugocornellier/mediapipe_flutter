/// Query per-task delegate support without loading a model.
library;

import 'package:mediapipe_flutter_core/capabilities.dart';
import 'src/capabilities/official_runtime_stub.dart'
    if (dart.library.io) 'src/capabilities/official_runtime_io.dart';
import 'src/interface/vision_types.dart';

export 'package:mediapipe_flutter_core/capabilities.dart'
    show TaskCapabilities, TaskPlatform;
export 'src/interface/vision_types.dart' show VisionDelegate;

/// Query the validated Hand, Gesture, Pose and Holistic task runtimes.
///
/// [useOfficialMacosRuntime] is reserved for Hand and Pose, the two tasks whose
/// official macOS runtime has been checked against the pinned reference. The
/// runtime probe fails closed if the build hook selected the source monolith.
Future<TaskCapabilities<VisionDelegate>> queryLandmarkTaskCapabilities({
  bool useOfficialMacosRuntime = false,
}) async => landmarkTaskCapabilitiesForPlatform(
  await currentTaskPlatform(),
  officialMacosRuntime:
      useOfficialMacosRuntime && hasOfficialMacosLandmarkRuntime(),
);

/// Evaluate landmark task CPU coverage without loading native code.
TaskCapabilities<VisionDelegate> landmarkTaskCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
}) => TaskCapabilities.onTargets(
  platform: platform,
  delegates: {
    VisionDelegate.cpu: {
      'linux/x64': null,
      'windows/x64': null,
      if (officialMacosRuntime) 'macos/arm64': '14.0',
    },
    VisionDelegate.gpu: const {},
  },
  runtimeVersion: '1.0.0',
  unavailableReasons: const {
    VisionDelegate.cpu:
        'Landmark task CPU inference requires Linux x64, Windows x64, or the '
        'official macOS landmark runtime. '
        'On macOS the source runtime is not validated against the official '
        'outputs; see upstream-issues.md UP-004.',
    VisionDelegate.gpu: 'Landmark task GPU inference has not been validated.',
  },
);

/// Query the validated Image Segmenter and legacy MagicTouch runtimes.
Future<TaskCapabilities<VisionDelegate>>
querySegmenterTaskCapabilities() async =>
    segmenterTaskCapabilitiesForPlatform(await currentTaskPlatform());

/// Evaluate segmenter task CPU coverage without loading native code.
///
/// This covers Image Segmenter and the stateless legacy MagicTouch API, not
/// the stateful `InteractiveSegmenter`, which has its own 1.0.1 runtime.
TaskCapabilities<VisionDelegate> segmenterTaskCapabilitiesForPlatform(
  TaskPlatform platform,
) => TaskCapabilities.onTargets(
  platform: platform,
  delegates: const {
    VisionDelegate.cpu: {'linux/x64': null, 'windows/x64': null},
    VisionDelegate.gpu: {},
  },
  runtimeVersion: '1.0.0',
  unavailableReasons: const {
    VisionDelegate.cpu:
        'Segmenter task CPU inference requires Linux x64 or Windows x64. '
        'On macOS the source runtime is not validated against the official '
        'outputs; see upstream-issues.md UP-004.',
    VisionDelegate.gpu: 'Segmenter task GPU inference has not been validated.',
  },
);

/// Query Image Classifier and Image Embedder's validated CPU runtimes.
Future<TaskCapabilities<VisionDelegate>> queryImageTaskCapabilities() async =>
    imageTaskCapabilitiesForPlatform(await currentTaskPlatform());

/// Evaluate the two image tasks without loading native code or a model.
TaskCapabilities<VisionDelegate> imageTaskCapabilitiesForPlatform(
  TaskPlatform platform,
) => TaskCapabilities.onTargets(
  platform: platform,
  delegates: const {
    VisionDelegate.cpu: {'linux/x64': null, 'windows/x64': null},
    VisionDelegate.gpu: {},
  },
  runtimeVersion: '1.0.0',
  unavailableReasons: const {
    VisionDelegate.cpu:
        'Image task CPU inference currently requires Linux x64 or Windows x64. '
        'The macOS source runtime no longer aborts in XNNPACK, but its CPU '
        'results still differ from the official outputs; see '
        'upstream-issues.md UP-004.',
    VisionDelegate.gpu: 'Image task GPU inference has not been validated.',
  },
);

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
/// CPU is validated on desktop x64; macOS arm64 supports Metal only.
TaskCapabilities<VisionDelegate> objectDetectorCapabilitiesForPlatform(
  TaskPlatform platform,
) => TaskCapabilities.onTargets(
  platform: platform,
  delegates: const {
    VisionDelegate.cpu: {'linux/x64': null, 'windows/x64': null},
    VisionDelegate.gpu: {'macos/arm64': '14.0'},
  },
  runtimeVersion: '1.0.0',
  unavailableReasons: {
    VisionDelegate.cpu: platform.operatingSystem == 'macos'
        ? 'The pinned macOS source build no longer aborts in XNNPACK\'s KleidiAI '
              'SME kernels, but its CPU results still differ from Google\'s '
              'official 1.0.0 outputs beyond tolerance. This task supports Metal '
              'only until that is resolved; see upstream-issues.md UP-001/UP-004.'
        : 'Object Detector CPU requires Linux x64 or Windows x64.',
    VisionDelegate.gpu:
        'Object Detector GPU is validated on macOS arm64 14.0+ only.',
  },
);
