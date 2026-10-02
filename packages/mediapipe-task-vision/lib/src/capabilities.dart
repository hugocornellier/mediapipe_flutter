/// Query per-task delegate support without loading a model.
library;

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';
import 'capabilities/official_runtime_stub.dart'
    if (dart.library.io) 'capabilities/official_runtime_io.dart';
import 'vision_task_backend.dart';

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
Future<TaskCapabilities> queryFaceLandmarkerCapabilities() async =>
    faceLandmarkerCapabilitiesForPlatform(await currentTaskPlatform());

/// Browser/Android support requires the corresponding registered SDK adapter.
TaskCapabilities faceLandmarkerCapabilitiesForPlatform(
  TaskPlatform platform,
) => TaskCapabilities.onTargets(
  platform: platform,
  delegates: {
    Delegate.cpu: {
      'macos/arm64': null,
      'linux/x64': null,
      'windows/x64': null,
      'ios/arm64': '15.0',
      if (faceLandmarkerBackendFactory != null) 'android/arm64': null,
      // Google's SDK ships x86_64; the emulator CI job runs it on the CPU.
      if (faceLandmarkerBackendFactory != null) 'android/x64': null,
      if (faceLandmarkerBackendFactory != null) 'web/unknown': null,
    },
    Delegate.gpu: {
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
    Delegate.cpu:
        'FaceLandmarker requires a supported official runtime and its platform adapter.',
    Delegate.gpu: platform.simulator
        ? _simulatorGpuGap
        : 'GPU requires macOS, Linux x64, Apple or Android SDKs, or the web '
              'adapter with worker WebGL 2 support.',
  },
);

/// Query Face Detector support on this process platform without a model.
Future<TaskCapabilities> queryFaceDetectorCapabilities() async =>
    faceDetectorCapabilitiesForPlatform(await currentTaskPlatform());

/// Face Detector runs where Face Landmarker does: the macOS and iOS face
/// runtimes, the Linux and Windows wheels, and the Android and web adapters.
TaskCapabilities faceDetectorCapabilitiesForPlatform(
  TaskPlatform platform,
) => TaskCapabilities.onTargets(
  platform: platform,
  delegates: {
    Delegate.cpu: {
      'macos/arm64': null,
      'linux/x64': null,
      'windows/x64': null,
      'ios/arm64': '15.0',
      if (faceDetectorBackendFactory != null) 'android/arm64': null,
      // Google's SDK ships x86_64; the emulator CI job runs it on the CPU.
      if (faceDetectorBackendFactory != null) 'android/x64': null,
      if (faceDetectorBackendFactory != null) 'web/unknown': null,
    },
    Delegate.gpu: {
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
    Delegate.cpu:
        'FaceDetector requires a supported official runtime and its platform '
        'adapter.',
    Delegate.gpu: platform.simulator
        ? _simulatorGpuGap
        : 'FaceDetector GPU requires macOS, Linux x64, the Apple or Android '
              'SDKs, or the web adapter.',
  },
);

/// Query Hand Landmarker support on this process platform without a model.
Future<TaskCapabilities> queryHandLandmarkerCapabilities() async =>
    handLandmarkerCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasMacosTasksRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Hand Landmarker runs on Google's official runtime on every target: the
/// Linux and Windows wheels, the opt-in macOS runtime, our adapter over the
/// iOS SDK, and the registered Android and web SDK adapters.
TaskCapabilities handLandmarkerCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
  bool officialIosRuntime = false,
}) {
  final sdkAdapter = handLandmarkerBackendFactory != null;
  return TaskCapabilities.onTargets(
    platform: platform,
    delegates: {
      Delegate.cpu: {
        'linux/x64': null,
        'windows/x64': null,
        if (officialMacosRuntime) 'macos/arm64': '14.0',
        if (officialIosRuntime) 'ios/arm64': '15.0',
        if (sdkAdapter) 'android/arm64': null,
        // Google's SDK ships x86_64; the emulator CI job runs it on the CPU.
        if (sdkAdapter) 'android/x64': null,
        if (sdkAdapter) 'web/unknown': null,
      },
      Delegate.gpu: {
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
      Delegate.cpu: platform.operatingSystem == 'macos'
          ? _macosEngineGap('HandLandmarker')
          : 'HandLandmarker requires Linux x64, Windows x64, macOS arm64, the '
                'official iOS SDK adapter, or the Android or web adapter '
                'package.',
      Delegate.gpu: officialIosRuntime && platform.simulator
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
Future<TaskCapabilities> queryPoseLandmarkerCapabilities() async =>
    poseLandmarkerCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasMacosTasksRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Pose Landmarker runs on Google's official runtime on every target, as
/// [handLandmarkerCapabilitiesForPlatform] describes. GPU is declared where
/// Google's platform SDK runs it; desktop GPU is not yet validated.
TaskCapabilities poseLandmarkerCapabilitiesForPlatform(
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
Future<TaskCapabilities> queryGestureRecognizerCapabilities() async =>
    gestureRecognizerCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasMacosTasksRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Gesture Recognizer, declared as [poseLandmarkerCapabilitiesForPlatform].
TaskCapabilities gestureRecognizerCapabilitiesForPlatform(
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
Future<TaskCapabilities> queryHolisticLandmarkerCapabilities() async =>
    holisticLandmarkerCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasMacosTasksRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Holistic Landmarker, declared as [poseLandmarkerCapabilitiesForPlatform].
TaskCapabilities holisticLandmarkerCapabilitiesForPlatform(
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
TaskCapabilities _sdkTaskCapabilities(
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
    Delegate.cpu: {
      'linux/x64': null,
      'windows/x64': null,
      if (officialMacosRuntime) 'macos/arm64': '14.0',
      if (officialIosRuntime) 'ios/arm64': '15.0',
      if (sdkAdapter) 'android/arm64': null,
      // Google's SDK ships x86_64; the emulator CI job runs it on the CPU.
      if (sdkAdapter) 'android/x64': null,
      if (sdkAdapter) 'web/unknown': null,
    },
    Delegate.gpu: {
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
    Delegate.cpu: platform.operatingSystem == 'macos'
        ? _macosEngineGap(name)
        : '$name requires Linux x64, Windows x64, macOS arm64, the official '
              'iOS SDK adapter, or the Android or web adapter package.',
    Delegate.gpu:
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

/// Query Image Segmenter support on this process platform without a model.
Future<TaskCapabilities> queryImageSegmenterCapabilities() async =>
    imageSegmenterCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasMacosTasksRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Image Segmenter, declared as [imageClassifierCapabilitiesForPlatform],
/// except on an Android PowerVR GPU: there Google's task aborts the app when it
/// converts a GPU result, which no caller can catch (upstream-issues.md
/// UP-023), so only the CPU is offered.
TaskCapabilities imageSegmenterCapabilitiesForPlatform(
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

/// Query Image Classifier support on this process platform without a model.
Future<TaskCapabilities> queryImageClassifierCapabilities() async =>
    imageClassifierCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasMacosTasksRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Image Classifier: CPU on the Linux and Windows wheels and Google's opt-in
/// macOS runtime, CPU and GPU through the iOS SDK adapter and the Android and
/// web adapters. The macOS source runtime is unvalidated; see UP-004.
TaskCapabilities imageClassifierCapabilitiesForPlatform(
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
Future<TaskCapabilities> queryImageEmbedderCapabilities() async =>
    imageEmbedderCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasMacosTasksRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Image Embedder, declared as [imageClassifierCapabilitiesForPlatform].
TaskCapabilities imageEmbedderCapabilitiesForPlatform(
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

/// Describe the package's stateful MagicTouch support on this process platform.
Future<TaskCapabilities> queryInteractiveSegmenterCapabilities() async =>
    interactiveSegmenterCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasMacosTasksRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Evaluate support for an explicit process platform snapshot: CPU on Google's
/// macOS engine and Linux wheel, the official iOS SDK adapter, and the
/// Android and web adapters. Google's Windows wheel lacks the stateful API.
TaskCapabilities interactiveSegmenterCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
  bool officialIosRuntime = false,
}) {
  final adapter = interactiveSegmenterBackendFactory != null;
  return TaskCapabilities.onTargets(
    platform: platform,
    delegates: {
      Delegate.cpu: {
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
      Delegate.gpu: {if (adapter) 'web/unknown': null},
    },
    runtimeVersion: tasksRuntimeVersionOn(platform),
    unavailableReasons: {
      Delegate.cpu: platform.operatingSystem == 'macos'
          ? _macosEngineGap('InteractiveSegmenter')
          : 'InteractiveSegmenter requires macOS arm64, Linux x64, the '
                'official iOS SDK adapter, or the Android or web adapter '
                'package.',
      Delegate.gpu: platform.operatingSystem == 'macos'
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
Future<TaskCapabilities> queryObjectDetectorCapabilities() async =>
    objectDetectorCapabilitiesForPlatform(
      await currentTaskPlatform(),
      officialMacosRuntime: hasMacosTasksRuntime(),
      officialIosRuntime: hasOfficialIosVisionRuntime(),
    );

/// Evaluate support for an explicit process platform snapshot: CPU on the
/// desktop wheels and Google's macOS engine, GPU on Linux's wheel and the
/// macOS engine, and both through the iOS SDK adapter and the Android and web
/// adapters.
TaskCapabilities objectDetectorCapabilitiesForPlatform(
  TaskPlatform platform, {
  bool officialMacosRuntime = false,
  bool officialIosRuntime = false,
}) => TaskCapabilities.onTargets(
  platform: platform,
  delegates: {
    Delegate.cpu: {
      'linux/x64': null,
      'windows/x64': null,
      if (officialMacosRuntime) 'macos/arm64': '14.0',
      if (officialIosRuntime) 'ios/arm64': '15.0',
      if (objectDetectorBackendFactory != null) 'android/arm64': null,
      // Google's SDK ships x86_64; the emulator CI job runs it on the CPU.
      if (objectDetectorBackendFactory != null) 'android/x64': null,
      if (objectDetectorBackendFactory != null) 'web/unknown': null,
    },
    Delegate.gpu: {
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
    Delegate.cpu: platform.operatingSystem == 'macos'
        ? _macosEngineGap('ObjectDetector')
        : 'Object Detector CPU requires Linux x64, Windows x64, macOS arm64, '
              'the official iOS SDK adapter, or the Android or web adapter '
              'package.',
    Delegate.gpu: officialIosRuntime && platform.simulator
        ? _simulatorGpuGap
        : platform.operatingSystem == 'macos'
        ? _macosEngineGap('ObjectDetector')
        : 'Object Detector GPU requires macOS arm64 14.0+, Linux x64, the '
              'official iOS SDK adapter, or the Android or web adapter.',
  },
);
