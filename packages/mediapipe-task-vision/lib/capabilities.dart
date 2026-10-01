/// Query per-task delegate support without loading a model.
library;

import 'package:mediapipe_core/capabilities.dart';
import 'src/capabilities/official_runtime_stub.dart'
    if (dart.library.io) 'src/capabilities/official_runtime_io.dart';
import 'src/face_landmarker_backend.dart';

export 'package:mediapipe_core/capabilities.dart'
    show TaskCapabilities, TaskPlatform;
export 'src/interface/vision_types.dart' show VisionDelegate;

/// Google's official Linux runtime is 1.0.1, the first with GPU built in;
/// the other desktop runtimes are 1.0.0.
String _desktopRuntimeVersion(TaskPlatform platform) =>
    platform.operatingSystem == 'linux' ? '1.0.1' : '1.0.0';

/// Why a task on Google's macOS engine is unavailable: the app has not turned
/// the engine on, which is opt-in on macOS because it is about 95 MB.
String _macosEngineGap(String name) => tasksRuntimeUnavailable(name, 'macos');

/// Why the iOS Simulator offers the CPU only: Google's iOS SDK aborts the app
/// there as soon as a GPU task processes an image, which no caller can catch.
/// Devices keep the GPU.
const _simulatorGpuGap =
    "Google's iOS SDK aborts the app on the iOS Simulator's GPU (Metal) path; "
    'use the CPU delegate on the simulator. iPhones and iPads run the GPU. See '
    'upstream-issues.md UP-031.';

/// Query official FaceLandmarker platform support without creating a task.
Future<TaskCapabilities<VisionDelegate>>
queryFaceLandmarkerCapabilities() async =>
    faceLandmarkerCapabilitiesForPlatform(await currentTaskPlatform());

/// Browser/Android support requires the corresponding registered SDK adapter.
TaskCapabilities<VisionDelegate> faceLandmarkerCapabilitiesForPlatform(
  TaskPlatform platform,
) => TaskCapabilities.onTargets(
  platform: platform,
  delegates: {
    VisionDelegate.cpu: {
      'macos/arm64': null,
      'linux/x64': null,
      'windows/x64': null,
      'ios/arm64': '15.0',
      if (faceLandmarkerBackendFactory != null) 'android/arm64': null,
      // Google's SDK ships x86_64; the emulator CI job runs it on the CPU.
      if (faceLandmarkerBackendFactory != null) 'android/x64': null,
      if (faceLandmarkerBackendFactory != null) 'web/unknown': null,
    },
    VisionDelegate.gpu: {
      'macos/arm64': '14.0',
      // Needs EGL and a GPU driver; Google refuses software renderers.
      'linux/x64': null,
      if (!platform.simulator) 'ios/arm64': '15.0',
      if (faceLandmarkerBackendFactory != null) 'android/arm64': null,
      if (faceLandmarkerBackendFactory != null) 'web/unknown': null,
    },
  },
  runtimeVersion: {'ios', 'web'}.contains(platform.operatingSystem)
      ? '1.0.1'
      : _desktopRuntimeVersion(platform),
  unavailableReasons: {
    VisionDelegate.cpu:
        'FaceLandmarker requires a supported official runtime and its platform adapter.',
    VisionDelegate.gpu: platform.simulator
        ? _simulatorGpuGap
        : 'GPU requires macOS, Linux x64, Apple or Android SDKs, or the web '
              'adapter with worker WebGL 2 support.',
  },
);

/// Query Face Detector support on this process platform without a model.
Future<TaskCapabilities<VisionDelegate>>
queryFaceDetectorCapabilities() async =>
    faceDetectorCapabilitiesForPlatform(await currentTaskPlatform());

/// Face Detector runs where Face Landmarker does: the macOS and iOS face
/// runtimes, the Linux and Windows wheels, and the Android and web adapters.
TaskCapabilities<VisionDelegate> faceDetectorCapabilitiesForPlatform(
  TaskPlatform platform,
) => TaskCapabilities.onTargets(
  platform: platform,
  delegates: {
    VisionDelegate.cpu: {
      'macos/arm64': null,
      'linux/x64': null,
      'windows/x64': null,
      'ios/arm64': '15.0',
      if (faceDetectorBackendFactory != null) 'android/arm64': null,
      // Google's SDK ships x86_64; the emulator CI job runs it on the CPU.
      if (faceDetectorBackendFactory != null) 'android/x64': null,
      if (faceDetectorBackendFactory != null) 'web/unknown': null,
    },
    VisionDelegate.gpu: {
      'macos/arm64': '14.0',
      // Needs EGL and a GPU driver; Google refuses software renderers.
      'linux/x64': null,
      if (!platform.simulator) 'ios/arm64': '15.0',
      if (faceDetectorBackendFactory != null) 'android/arm64': null,
      if (faceDetectorBackendFactory != null) 'web/unknown': null,
    },
  },
  runtimeVersion: {'ios', 'web'}.contains(platform.operatingSystem)
      ? '1.0.1'
      : _desktopRuntimeVersion(platform),
  unavailableReasons: {
    VisionDelegate.cpu:
        'FaceDetector requires a supported official runtime and its platform '
        'adapter.',
    VisionDelegate.gpu: platform.simulator
        ? _simulatorGpuGap
        : 'FaceDetector GPU requires macOS, Linux x64, the Apple or Android '
              'SDKs, or the web adapter.',
  },
);

/// Query Hand Landmarker support on this process platform without a model.
Future<TaskCapabilities<VisionDelegate>>
queryHandLandmarkerCapabilities() async =>
    handLandmarkerCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasOfficialMacosLandmarkRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Hand Landmarker runs on Google's official runtime on every target: the
/// Linux and Windows wheels, the opt-in macOS runtime, our adapter over the
/// iOS SDK, and the registered Android and web SDK adapters.
TaskCapabilities<VisionDelegate> handLandmarkerCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
  bool officialIosRuntime = false,
}) {
  final sdkAdapter = handLandmarkerBackendFactory != null;
  return TaskCapabilities.onTargets(
    platform: platform,
    delegates: {
      VisionDelegate.cpu: {
        'linux/x64': null,
        'windows/x64': null,
        if (officialMacosRuntime) 'macos/arm64': '14.0',
        if (officialIosRuntime) 'ios/arm64': '15.0',
        if (sdkAdapter) 'android/arm64': null,
        // Google's SDK ships x86_64; the emulator CI job runs it on the CPU.
        if (sdkAdapter) 'android/x64': null,
        if (sdkAdapter) 'web/unknown': null,
      },
      VisionDelegate.gpu: {
        // Needs EGL and a GPU driver; Google refuses software renderers.
        'linux/x64': null,
        if (officialMacosRuntime) 'macos/arm64': '14.0',
        if (officialIosRuntime && !platform.simulator) 'ios/arm64': '15.0',
        if (sdkAdapter) 'android/arm64': null,
        if (sdkAdapter) 'web/unknown': null,
      },
    },
    runtimeVersion: {'ios', 'web'}.contains(platform.operatingSystem)
        ? '1.0.1'
        : _desktopRuntimeVersion(platform),
    unavailableReasons: {
      VisionDelegate.cpu: platform.operatingSystem == 'macos'
          ? _macosEngineGap('HandLandmarker')
          : 'HandLandmarker requires Linux x64, Windows x64, macOS arm64, the '
                'official iOS SDK adapter, or the Android or web adapter '
                'package.',
      VisionDelegate.gpu: officialIosRuntime && platform.simulator
          ? _simulatorGpuGap
          : platform.operatingSystem == 'macos'
          ? _macosEngineGap('HandLandmarker')
          : 'HandLandmarker GPU requires Linux x64, macOS arm64, the official '
                'iOS SDK adapter, or the Android or web adapter; Windows has no '
                'GPU runtime.',
    },
  );
}

/// Query Pose Landmarker support on this process platform without a model.
Future<TaskCapabilities<VisionDelegate>>
queryPoseLandmarkerCapabilities() async =>
    poseLandmarkerCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasOfficialMacosLandmarkRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Pose Landmarker runs on Google's official runtime on every target, as
/// [handLandmarkerCapabilitiesForPlatform] describes. GPU is declared where
/// Google's platform SDK runs it; desktop GPU is not yet validated.
TaskCapabilities<VisionDelegate> poseLandmarkerCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
  bool officialIosRuntime = false,
}) => _sdkTaskCapabilities(
  platform,
  'PoseLandmarker',
  sdkAdapter: poseLandmarkerBackendFactory != null,
  officialMacosRuntime: officialMacosRuntime,
  officialIosRuntime: officialIosRuntime,
  linuxGpu: true,
  macosGpu: true,
);

/// Query Gesture Recognizer support on this process platform without a model.
Future<TaskCapabilities<VisionDelegate>>
queryGestureRecognizerCapabilities() async =>
    gestureRecognizerCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasOfficialMacosLandmarkRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Gesture Recognizer, declared as [poseLandmarkerCapabilitiesForPlatform].
TaskCapabilities<VisionDelegate> gestureRecognizerCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
  bool officialIosRuntime = false,
}) => _sdkTaskCapabilities(
  platform,
  'GestureRecognizer',
  sdkAdapter: gestureRecognizerBackendFactory != null,
  officialMacosRuntime: officialMacosRuntime,
  officialIosRuntime: officialIosRuntime,
  linuxGpu: true,
  macosGpu: true,
);

/// Query Holistic Landmarker support on this process platform without a model.
Future<TaskCapabilities<VisionDelegate>>
queryHolisticLandmarkerCapabilities() async =>
    holisticLandmarkerCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasOfficialMacosLandmarkRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Holistic Landmarker, declared as [poseLandmarkerCapabilitiesForPlatform].
TaskCapabilities<VisionDelegate> holisticLandmarkerCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
  bool officialIosRuntime = false,
}) => _sdkTaskCapabilities(
  platform,
  'HolisticLandmarker',
  sdkAdapter: holisticLandmarkerBackendFactory != null,
  officialMacosRuntime: officialMacosRuntime,
  officialIosRuntime: officialIosRuntime,
  desktopGpuGap:
      'Google\'s desktop runtimes cannot open its face blendshapes model on '
      'GPU (upstream-issues.md UP-026).',
);

/// CPU on the desktop wheels, Google's macOS engine, the iOS SDK adapter and
/// the registered Android and web adapters; GPU on the platform SDKs, and
/// with [linuxGpu] on Linux's wheel (OpenGL ES, needing EGL and a GPU driver)
/// and with [macosGpu] on Google's macOS engine (Metal), where CI
/// compares it with Google's own GPU output on the same machine. An
/// [androidGpuGap] withdraws the Android GPU and is the reason reported; the
/// iOS Simulator always loses the GPU ([_simulatorGpuGap]).
TaskCapabilities<VisionDelegate> _sdkTaskCapabilities(
  TaskPlatform platform,
  String name, {
  required bool sdkAdapter,
  required bool officialMacosRuntime,
  required bool officialIosRuntime,
  bool linuxGpu = false,
  bool macosGpu = false,
  String? desktopGpuGap,
  String? androidGpuGap,
}) => TaskCapabilities.onTargets(
  platform: platform,
  delegates: {
    VisionDelegate.cpu: {
      'linux/x64': null,
      'windows/x64': null,
      if (officialMacosRuntime) 'macos/arm64': '14.0',
      if (officialIosRuntime) 'ios/arm64': '15.0',
      if (sdkAdapter) 'android/arm64': null,
      // Google's SDK ships x86_64; the emulator CI job runs it on the CPU.
      if (sdkAdapter) 'android/x64': null,
      if (sdkAdapter) 'web/unknown': null,
    },
    VisionDelegate.gpu: {
      if (linuxGpu) 'linux/x64': null,
      if (macosGpu && officialMacosRuntime) 'macos/arm64': '14.0',
      if (officialIosRuntime && !platform.simulator) 'ios/arm64': '15.0',
      if (sdkAdapter && androidGpuGap == null) 'android/arm64': null,
      if (sdkAdapter) 'web/unknown': null,
    },
  },
  runtimeVersion: {'ios', 'web'}.contains(platform.operatingSystem)
      ? '1.0.1'
      : _desktopRuntimeVersion(platform),
  unavailableReasons: {
    VisionDelegate.cpu: platform.operatingSystem == 'macos'
        ? _macosEngineGap(name)
        : '$name requires Linux x64, Windows x64, macOS arm64, the official '
              'iOS SDK adapter, or the Android or web adapter package.',
    VisionDelegate.gpu:
        androidGpuGap ??
        (officialIosRuntime && platform.simulator ? _simulatorGpuGap : null) ??
        (platform.operatingSystem == 'macos' && !officialMacosRuntime
            ? _macosEngineGap(name)
            : null) ??
        [
          '$name GPU requires',
          if (linuxGpu) 'Linux x64,',
          if (macosGpu) 'macOS arm64,',
          'the official iOS SDK adapter, or the Android or web adapter.',
          ?desktopGpuGap,
        ].join(' '),
  },
);

/// Whether [platform] is an Android device whose GPU is Imagination's PowerVR,
/// as the Android adapter names it.
bool _androidPowerVr(TaskPlatform platform) {
  final gpu = platform.gpu?.toLowerCase() ?? '';
  return platform.operatingSystem == 'android' &&
      (gpu.contains('powervr') || gpu.contains('imagination'));
}

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
  runtimeVersion: _desktopRuntimeVersion(platform),
  unavailableReasons: const {
    VisionDelegate.cpu:
        'Landmark task CPU inference requires Linux x64, Windows x64, or '
        "Google's macOS engine (mediapipe_core.tasks_runtime: true).",
    VisionDelegate.gpu: 'Landmark task GPU inference has not been validated.',
  },
);

/// Query Image Segmenter support on this process platform without a model.
Future<TaskCapabilities<VisionDelegate>>
queryImageSegmenterCapabilities() async =>
    imageSegmenterCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasOfficialMacosLandmarkRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Image Segmenter, declared as [imageClassifierCapabilitiesForPlatform],
/// except on an Android PowerVR GPU: there Google's task aborts the app when it
/// converts a GPU result, which no caller can catch (upstream-issues.md
/// UP-023), so only the CPU is offered.
TaskCapabilities<VisionDelegate> imageSegmenterCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
  bool officialIosRuntime = false,
}) => _sdkTaskCapabilities(
  platform,
  'ImageSegmenter',
  sdkAdapter: imageSegmenterBackendFactory != null,
  officialMacosRuntime: officialMacosRuntime,
  officialIosRuntime: officialIosRuntime,
  linuxGpu: true,
  macosGpu: true,
  androidGpuGap: _androidPowerVr(platform)
      ? "Google's Android Image Segmenter aborts the app on this PowerVR GPU "
            '(${platform.gpu}); use the CPU delegate. See upstream-issues.md '
            'UP-023.'
      : null,
);

// TODO: Delete with InteractiveSegmenterLegacy; only the modern
// InteractiveSegmenter is needed. See InteractiveSegmenterLegacyOptions.
/// Query Interactive Segmenter Legacy support on this process platform.
Future<TaskCapabilities<VisionDelegate>>
queryInteractiveSegmenterLegacyCapabilities() async =>
    interactiveSegmenterLegacyCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasOfficialMacosLandmarkRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// The stateless legacy MagicTouch API, declared as
/// [imageSegmenterCapabilitiesForPlatform]. The Android adapter does not
/// serve it: Google's Android 1.0.0 task ignores the keypoint
/// (upstream-issues.md UP-020).
TaskCapabilities<VisionDelegate>
interactiveSegmenterLegacyCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
  bool officialIosRuntime = false,
}) => _sdkTaskCapabilities(
  platform,
  'InteractiveSegmenterLegacy',
  sdkAdapter: interactiveSegmenterLegacyBackendFactory != null,
  officialMacosRuntime: officialMacosRuntime,
  officialIosRuntime: officialIosRuntime,
);

/// Evaluate segmenter task CPU coverage on the desktop wheels without loading
/// native code. Image Segmenter and the legacy MagicTouch API have their own
/// rules, which add the SDK adapters; the stateful `InteractiveSegmenter` has
/// its own 1.0.1 runtime.
TaskCapabilities<VisionDelegate> segmenterTaskCapabilitiesForPlatform(
  TaskPlatform platform,
) => TaskCapabilities.onTargets(
  platform: platform,
  delegates: const {
    VisionDelegate.cpu: {'linux/x64': null, 'windows/x64': null},
    VisionDelegate.gpu: {},
  },
  runtimeVersion: _desktopRuntimeVersion(platform),
  unavailableReasons: const {
    VisionDelegate.cpu:
        'Segmenter task CPU inference requires Linux x64 or Windows x64.',
    VisionDelegate.gpu: 'Segmenter task GPU inference has not been validated.',
  },
);

/// Query Image Classifier support on this process platform without a model.
Future<TaskCapabilities<VisionDelegate>>
queryImageClassifierCapabilities() async =>
    imageClassifierCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasOfficialMacosLandmarkRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Image Classifier: CPU on the Linux and Windows wheels and Google's opt-in
/// macOS runtime, CPU and GPU through the iOS SDK adapter and the Android and
/// web adapters. The macOS source runtime is unvalidated; see UP-004.
TaskCapabilities<VisionDelegate> imageClassifierCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
  bool officialIosRuntime = false,
}) => _sdkTaskCapabilities(
  platform,
  'ImageClassifier',
  sdkAdapter: imageClassifierBackendFactory != null,
  officialMacosRuntime: officialMacosRuntime,
  officialIosRuntime: officialIosRuntime,
  linuxGpu: true,
  macosGpu: true,
);

/// Query Image Embedder support on this process platform without a model.
Future<TaskCapabilities<VisionDelegate>>
queryImageEmbedderCapabilities() async => imageEmbedderCapabilitiesForPlatform(
  await currentTaskPlatform(),
  officialMacosRuntime: hasOfficialMacosLandmarkRuntime(),
  officialIosRuntime: hasOfficialIosVisionRuntime(),
);

/// Image Embedder, declared as [imageClassifierCapabilitiesForPlatform].
TaskCapabilities<VisionDelegate> imageEmbedderCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
  bool officialIosRuntime = false,
}) => _sdkTaskCapabilities(
  platform,
  'ImageEmbedder',
  sdkAdapter: imageEmbedderBackendFactory != null,
  officialMacosRuntime: officialMacosRuntime,
  officialIosRuntime: officialIosRuntime,
  macosGpu: true,
  desktopGpuGap:
      'Google\'s Linux runtime aborts on GPU (upstream-issues.md UP-027).',
);

/// Evaluate the two image tasks without loading native code or a model.
TaskCapabilities<VisionDelegate> imageTaskCapabilitiesForPlatform(
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
  runtimeVersion: _desktopRuntimeVersion(platform),
  unavailableReasons: const {
    VisionDelegate.cpu:
        'Image task CPU inference requires Linux x64, Windows x64, or '
        "Google's macOS engine (mediapipe_core.tasks_runtime: true).",
    VisionDelegate.gpu: 'Image task GPU inference has not been validated.',
  },
);

/// Describe the package's stateful MagicTouch support on this process platform.
Future<TaskCapabilities<VisionDelegate>>
queryInteractiveSegmenterCapabilities() async =>
    interactiveSegmenterCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasOfficialMacosLandmarkRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Evaluate support for an explicit process platform snapshot: CPU on Google's
/// macOS engine and Linux wheel, the official iOS SDK adapter, and the
/// Android and web adapters. Google's Windows wheel lacks the stateful API.
TaskCapabilities<VisionDelegate> interactiveSegmenterCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
  bool officialIosRuntime = false,
}) {
  final adapter = interactiveSegmenterBackendFactory != null;
  return TaskCapabilities.onTargets(
    platform: platform,
    delegates: {
      VisionDelegate.cpu: {
        if (officialMacosRuntime) ...macosTasksRuntimeTargets,
        // Google's Linux wheel, which core bundles, exports the stateful API.
        'linux/x64': null,
        if (officialIosRuntime) 'ios/arm64': '15.0',
        if (adapter) 'android/arm64': null,
        if (adapter) 'android/x64': null,
        if (adapter) 'web/unknown': null,
      },
      // Google's browser task runs MagicTouch on WebGL 2, as its sample does
      // by default. Its mobile SDKs run it on CPU.
      VisionDelegate.gpu: {if (adapter) 'web/unknown': null},
    },
    runtimeVersion: tasksRuntimeVersionOn(platform),
    unavailableReasons: {
      VisionDelegate.cpu: platform.operatingSystem == 'macos'
          ? _macosEngineGap('InteractiveSegmenter')
          : 'InteractiveSegmenter requires macOS arm64, Linux x64, the '
                'official iOS SDK adapter, or the Android or web adapter '
                'package.',
      VisionDelegate.gpu: platform.operatingSystem == 'macos'
          ? 'The official MediaPipe macOS GPU stroke shader requests GLSL 330 in '
                'an OpenGL 2.1 context and fails to compile. Confirmed on both '
                'the 1.0.0 and 1.0.1 official runtimes, so it is not fixed by '
                'changing version. Metal itself is fine; only GL-shader '
                'calculators are affected. This task supports CPU only (see '
                'upstream-issues.md UP-008).'
          : 'Interactive Segmenter GPU runs in browsers only; elsewhere it '
                'supports CPU only.',
    },
  );
}

/// Describe the package's Object Detector support on this process platform.
Future<TaskCapabilities<VisionDelegate>>
queryObjectDetectorCapabilities() async =>
    objectDetectorCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasOfficialMacosLandmarkRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Evaluate support for an explicit process platform snapshot: CPU on the
/// desktop wheels and Google's macOS engine, GPU on Linux's wheel and the
/// macOS engine, and both through the iOS SDK adapter and the Android and web
/// adapters.
TaskCapabilities<VisionDelegate> objectDetectorCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
  bool officialIosRuntime = false,
}) => TaskCapabilities.onTargets(
  platform: platform,
  delegates: {
    VisionDelegate.cpu: {
      'linux/x64': null,
      'windows/x64': null,
      if (officialMacosRuntime) 'macos/arm64': '14.0',
      if (officialIosRuntime) 'ios/arm64': '15.0',
      if (objectDetectorBackendFactory != null) 'android/arm64': null,
      // Google's SDK ships x86_64; the emulator CI job runs it on the CPU.
      if (objectDetectorBackendFactory != null) 'android/x64': null,
      if (objectDetectorBackendFactory != null) 'web/unknown': null,
    },
    VisionDelegate.gpu: {
      if (officialMacosRuntime) 'macos/arm64': '14.0',
      // Needs EGL and a GPU driver; Google refuses software renderers.
      'linux/x64': null,
      if (officialIosRuntime && !platform.simulator) 'ios/arm64': '15.0',
      if (objectDetectorBackendFactory != null) 'android/arm64': null,
      if (objectDetectorBackendFactory != null) 'web/unknown': null,
    },
  },
  runtimeVersion: {'ios', 'web'}.contains(platform.operatingSystem)
      ? '1.0.1'
      : _desktopRuntimeVersion(platform),
  unavailableReasons: {
    VisionDelegate.cpu: platform.operatingSystem == 'macos'
        ? _macosEngineGap('ObjectDetector')
        : 'Object Detector CPU requires Linux x64, Windows x64, macOS arm64, '
              'the official iOS SDK adapter, or the Android or web adapter '
              'package.',
    VisionDelegate.gpu: officialIosRuntime && platform.simulator
        ? _simulatorGpuGap
        : platform.operatingSystem == 'macos'
        ? _macosEngineGap('ObjectDetector')
        : 'Object Detector GPU requires macOS arm64 14.0+, Linux x64, the '
              'official iOS SDK adapter, or the Android or web adapter.',
  },
);
