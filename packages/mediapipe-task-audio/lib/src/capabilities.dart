/// Audio Classifier's delegate support, queried without loading a model.
library;

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import 'audio_task_backend.dart' show audioTaskBackendFactory;

/// Where Audio Classifier runs: CPU on core's shared runtime, Google's library
/// for macOS arm64 (macOS 14+), Linux x64 and Windows x64 and its iOS SDK
/// (iOS 15+, through the adapter core builds), and through Google's
/// browser runtime or Android SDK where a platform plugin installs it.
Future<TaskCapabilities> queryAudioClassifierCapabilities() async =>
    audioClassifierCapabilitiesForPlatform(await currentTaskPlatform());

/// Audio Classifier support on [platform], without loading code.
TaskCapabilities audioClassifierCapabilitiesForPlatform(
  TaskPlatform platform,
) => TaskCapabilities.cpuOnTargets(
  platform: platform,
  gpuUnavailableReason: "Google's official audio task runs on CPU only.",
  runtimeVersion: tasksRuntimeVersionOn(platform),
  targets: {
    // Core's runtime, iOS included (its SDK adapter).
    ...tasksRuntimeTargets,
    // A registered backend is Google's browser runtime or Android SDK for
    // this very platform.
    if (audioTaskBackendFactory != null) ...{
      'web/unknown': null,
      'android/arm64': null,
      'android/x64': null,
    },
  },
);
