/// Decision Maker's delegate support, queried without loading a model.
library;

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import '../models.dart' show DecisionModels;
import 'decision_backend.dart' show decisionBackendFactory;

/// The release behind Decision Maker on every platform: Google's per-family
/// decision library (its delivery of October 8, 2026) on Android, iOS,
/// macOS and Linux, its 1.1.0 wheel's library on Windows, and
/// `@mediapipe/tasks-decision` 1.1.0 in browsers.
const decisionRuntimeVersion = '1.1.0';

/// Where Google's C library with Decision Maker runs: core's shared targets,
/// from its per-family library (`familyRuntimes`) everywhere but Windows,
/// where core's `wheelRuntimes` pins the wheel's library.
const decisionRuntimeTargets = tasksRuntimeTargets;

/// Where Google's native runtime accepts the text-only EmbeddingGemma 2
/// model (`DecisionModels.embeddingGemma2Text`): Windows, on the library
/// from Google's wheel. Browsers accept it too. Google's per-family decision
/// library, the runtime on the other targets, fails every evaluation with it
/// (upstream-issues.md UP-053); `DecisionModels.embeddingGemma2TextVision`
/// answers the same everywhere.
const embeddingGemma2TextTargets = <String, String?>{'windows/x64': null};

/// Why the text-only EmbeddingGemma 2 model is unavailable on Google's
/// per-family library, and what to use instead (UP-053).
const textOnlyEmbeddingGemmaUnavailable =
    "Google's per-family decision library, the runtime on Android, iOS, "
    'macOS and Linux, fails every evaluation with the text-only '
    'EmbeddingGemma 2 model (upstream-issues.md UP-053). Use '
    'DecisionModels.embeddingGemma2TextVision, the same text encoder with a '
    'vision encoder the task never runs, which answers the same on every '
    'runtime, or Laya.';

const _noLibrary =
    "Google's Decision Maker library covers Android arm64 and x86_64, iOS, "
    'macOS arm64, Linux x64 and Windows x64, and browsers run its JavaScript '
    'runtime.';

/// Google's browser runtime fails on the CPU (upstream-issues.md UP-049).
const _browserCpu =
    "Google's browser Decision Maker (@mediapipe/tasks-decision 1.1.0) fails "
    'every evaluation on the CPU delegate (upstream-issues.md UP-049). Use '
    'Delegate.gpu, its WebGPU path, as Google\'s web demo does.';

/// How the web plugin names a WebGPU adapter in `TaskPlatform.gpu`.
const webGpuAdapterPrefix = 'WebGPU';

/// The adapters Google's runtime refuses to run on, by Google's own rule.
final _softwareAdapter = RegExp(
  r'fallback|swiftshader|llvmpipe|software|lavapipe',
  caseSensitive: false,
);

/// Whether [platform] names a hardware WebGPU adapter, the only one Google's
/// browser Decision Maker answers on (UP-049).
bool _hardwareWebGpu(TaskPlatform platform) => switch (platform.gpu) {
  final gpu? =>
    gpu.startsWith(webGpuAdapterPrefix) && !_softwareAdapter.hasMatch(gpu),
  null => false,
};

const _desktopGpu =
    "Google's library runs Decision Maker on the CPU; this package has not "
    'validated its GPU path.';

const _noPlugin =
    'The MediaPipe Decision browser plugin did not register. Depend on '
    'mediapipe_decision as a Flutter plugin.';

String _noWebGpu(TaskPlatform platform) =>
    "Google's browser Decision Maker answers only on a hardware WebGPU "
    'adapter; without one it falls back to its CPU path, where every '
    'evaluation fails (upstream-issues.md UP-049). This browser has '
    '${platform.gpu ?? 'no WebGPU adapter'}.';

/// Query Decision Maker support on this platform without loading a model.
/// Pass [model] to learn where that model runs: the text-only EmbeddingGemma
/// 2 (`DecisionModels.embeddingGemma2Text`) only on Windows and in browsers
/// (UP-053); every other pinned model wherever the task runs.
Future<TaskCapabilities> queryDecisionMakerCapabilities([
  DownloadAsset? model,
]) async => decisionMakerCapabilitiesForPlatform(
  await currentTaskPlatform(),
  model: model,
);

/// Decision Maker support on [platform]: the CPU on Google's native
/// libraries, and the GPU in browsers once the plugin registers, since
/// Google's browser runtime fails on the CPU (UP-049). With [model], the
/// support for that model: Google's per-family library fails every
/// evaluation with the text-only EmbeddingGemma 2 (UP-053).
TaskCapabilities decisionMakerCapabilitiesForPlatform(
  TaskPlatform platform, {
  DownloadAsset? model,
}) {
  final web = platform.operatingSystem == 'web';
  final textOnlyGemma =
      model?.sha256 == DecisionModels.embeddingGemma2Text.sha256;
  // The library here has the task but not this model.
  final libraryRefusesModel =
      textOnlyGemma &&
      decisionRuntimeTargets.containsKey(platform.target) &&
      !embeddingGemma2TextTargets.containsKey(platform.target);
  return TaskCapabilities.onTargets(
    platform: platform,
    delegates: {
      Delegate.cpu: textOnlyGemma
          ? embeddingGemma2TextTargets
          : decisionRuntimeTargets,
      Delegate.gpu: {
        if (decisionBackendFactory != null && _hardwareWebGpu(platform))
          'web/unknown': null,
      },
    },
    unavailableReasons: {
      // Without a hardware adapter both delegates end on Google's CPU path.
      Delegate.cpu: !web
          ? libraryRefusesModel
                ? textOnlyEmbeddingGemmaUnavailable
                : _noLibrary
          : _hardwareWebGpu(platform)
          ? _browserCpu
          : _noWebGpu(platform),
      Delegate.gpu: web
          ? decisionBackendFactory == null
                ? _noPlugin
                : _noWebGpu(platform)
          : libraryRefusesModel
          ? textOnlyEmbeddingGemmaUnavailable
          : decisionRuntimeTargets.containsKey(platform.target)
          ? _desktopGpu
          : _noLibrary,
    },
    runtimeVersion: decisionRuntimeVersion,
  );
}
