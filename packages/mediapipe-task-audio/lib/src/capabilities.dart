/// Audio Classifier's delegate support, queried without loading a model.
library;

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import 'audio_task_backend.dart' show audioTaskBackendFactory;

/// Where Audio Classifier runs: CPU on Google's audio library on Android,
/// iOS 15+, macOS 14+ arm64, Linux x64 and Windows x64, and through Google's
/// browser runtime where the web plugin installs it.
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
    ...tasksRuntimeTargets,
    // A registered backend is Google's browser runtime.
    if (audioTaskBackendFactory != null) 'web/unknown': null,
  },
);

/// Where Google's speech tasks run: core's 64-bit targets, whose library
/// has Audio Transcriber and Text to Speech since 1.2.2.
const speechRuntimeTargets = largeModelRuntimeTargets;

const _speech32Bit =
    "Google's speech models need more memory than a 32-bit Android process "
    '(armeabi-v7a) holds, so the speech tasks run on 64-bit Android '
    '(arm64-v8a or x86_64).';

const _speechNoLibrary =
    "Google's audio library has the speech tasks on Android arm64 and "
    'x86_64, iOS, macOS arm64, Linux x64 and Windows x64.';

const _speechNoBrowser =
    "Google's browser runtime (@mediapipe/tasks-audio) has no Audio "
    'Transcriber or Text to Speech.';

const _speechGpu =
    "Google's speech tasks run on the CPU; this package has not validated a "
    'GPU path.';

/// Where Audio Transcriber runs: CPU on Google's audio library on 64-bit
/// Android, iOS 15+, macOS 14+ arm64, Linux x64 and Windows x64. Browsers
/// have none.
Future<TaskCapabilities> queryAudioTranscriberCapabilities() async =>
    audioTranscriberCapabilitiesForPlatform(await currentTaskPlatform());

/// Audio Transcriber support on [platform], without loading code.
TaskCapabilities audioTranscriberCapabilitiesForPlatform(
  TaskPlatform platform,
) => _speechCapabilities(platform);

/// Where Text to Speech runs: CPU on Google's audio library on 64-bit
/// Android, iOS 15+, macOS 14+ arm64, Linux x64 and Windows x64. Browsers
/// have none.
Future<TaskCapabilities> queryTextToSpeechCapabilities() async =>
    textToSpeechCapabilitiesForPlatform(await currentTaskPlatform());

/// Text to Speech support on [platform], without loading code.
TaskCapabilities textToSpeechCapabilitiesForPlatform(TaskPlatform platform) =>
    _speechCapabilities(platform);

TaskCapabilities _speechCapabilities(TaskPlatform platform) {
  final reason = platform.operatingSystem == 'web'
      ? _speechNoBrowser
      : platform.target == 'android/arm'
      ? _speech32Bit
      : _speechNoLibrary;
  return TaskCapabilities.onTargets(
    platform: platform,
    delegates: {Delegate.cpu: speechRuntimeTargets, Delegate.gpu: const {}},
    unavailableReasons: {
      Delegate.cpu: reason,
      Delegate.gpu: speechRuntimeTargets.containsKey(platform.target)
          ? _speechGpu
          : reason,
    },
    runtimeVersion: tasksRuntimeVersionOn(platform),
  );
}
