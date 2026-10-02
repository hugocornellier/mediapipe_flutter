/// Per-task delegate support, queried without loading a model.
library;

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import '../models.dart' show TextModels;
import 'text_task_backend.dart' show textTaskBackendFactory;

/// Where a registered platform backend serves the text tasks: Google's
/// Android SDK, and in browsers its JavaScript runtime.
const _androidTargets = <String, String?>{
  'android/arm64': null,
  'android/x64': null,
};

/// CPU wherever core's runtime or a registered platform backend serves the
/// task; every text task runs on the CPU only.
TaskCapabilities _onEveryRuntime(
  TaskPlatform platform, {
  required String gpuUnavailableReason,
}) => TaskCapabilities.cpuOnTargets(
  platform: platform,
  gpuUnavailableReason: gpuUnavailableReason,
  runtimeVersion: tasksRuntimeVersionOn(platform),
  targets: {
    ...tasksRuntimeTargets,
    if (textTaskBackendFactory != null) ...{
      'web/unknown': null,
      ..._androidTargets,
    },
  },
);

const _classicGpu = 'The official classic text tasks run on CPU only.';

/// Google's browser text runtime (`@mediapipe/tasks-text` 1.0.1) has no
/// Proofreader or Summarizer; see upstream-issues.md UP-034.
const _noBrowserGenerativeTasks =
    "Google's browser text runtime has no Proofreader or Summarizer "
    '(upstream-issues.md UP-034). Run the task on Android, iOS, macOS, '
    'Linux or Windows.';

/// The Proofreader and Summarizer: CPU wherever core's runtime serves them
/// (macOS, Linux, Windows and iOS) and on Google's Android SDK through the
/// registered backend; browsers have neither task.
TaskCapabilities _generative(TaskPlatform platform) {
  const gpu = "Google's task accepts only the CPU delegate.";
  final targets = <String, String?>{
    ...tasksRuntimeTargets,
    if (textTaskBackendFactory != null) ..._androidTargets,
  };
  if (platform.operatingSystem == 'web') {
    return TaskCapabilities.onTargets(
      platform: platform,
      delegates: {Delegate.cpu: targets, Delegate.gpu: const {}},
      unavailableReasons: const {
        Delegate.cpu: _noBrowserGenerativeTasks,
        Delegate.gpu: _noBrowserGenerativeTasks,
      },
      runtimeVersion: tasksRuntimeVersionOn(platform),
    );
  }
  return TaskCapabilities.cpuOnTargets(
    platform: platform,
    gpuUnavailableReason: gpu,
    runtimeVersion: tasksRuntimeVersionOn(platform),
    targets: targets,
  );
}

/// Query Text Classifier support on this platform without a model.
Future<TaskCapabilities> queryTextClassifierCapabilities() async =>
    textClassifierCapabilitiesForPlatform(await currentTaskPlatform());

/// Text Classifier support on [platform]: CPU on core's runtime and the
/// registered browser and Android backends.
TaskCapabilities textClassifierCapabilitiesForPlatform(TaskPlatform platform) =>
    _onEveryRuntime(platform, gpuUnavailableReason: _classicGpu);

/// Query Language Detector support on this platform without a model.
Future<TaskCapabilities> queryLanguageDetectorCapabilities() async =>
    languageDetectorCapabilitiesForPlatform(await currentTaskPlatform());

/// Language Detector support on [platform], as for the Text Classifier.
TaskCapabilities languageDetectorCapabilitiesForPlatform(
  TaskPlatform platform,
) => _onEveryRuntime(platform, gpuUnavailableReason: _classicGpu);

/// Query Text Embedder support on this platform for [model]: pass
/// `TextModels.embeddingGemma` to learn where EmbeddingGemma runs.
Future<TaskCapabilities> queryTextEmbedderCapabilities([
  DownloadAsset? model,
]) async => textEmbedderCapabilitiesForPlatform(
  await currentTaskPlatform(),
  model: model,
);

/// Text Embedder support on [platform]: CPU on core's runtime and the
/// registered browser and Android backends, for the classic embedders and
/// EmbeddingGemma alike. Every runtime formats EmbeddingGemma's prompts.
TaskCapabilities textEmbedderCapabilitiesForPlatform(
  TaskPlatform platform, {
  DownloadAsset? model,
}) => _onEveryRuntime(
  platform,
  gpuUnavailableReason: model?.sha256 == TextModels.embeddingGemma.sha256
      ? "Google's EmbeddingGemma pipeline runs on the CPU only; its macOS "
            'Metal interpreter fails during creation (observed with '
            'MediaPipe 1.0.1).'
      : _classicGpu,
);

/// Query Proofreader support on this platform without a model.
Future<TaskCapabilities> queryTextProofreaderCapabilities() async =>
    textProofreaderCapabilitiesForPlatform(await currentTaskPlatform());

/// Proofreader support on [platform]: CPU on core's runtime and Google's
/// Android SDK; browsers have no Proofreader.
TaskCapabilities textProofreaderCapabilitiesForPlatform(
  TaskPlatform platform,
) => _generative(platform);

/// Query Summarizer support on this platform without a model.
Future<TaskCapabilities> queryTextSummarizerCapabilities() async =>
    textSummarizerCapabilitiesForPlatform(await currentTaskPlatform());

/// Summarizer support on [platform]: CPU on core's runtime and Google's
/// Android SDK; browsers have no Summarizer.
TaskCapabilities textSummarizerCapabilitiesForPlatform(TaskPlatform platform) =>
    _generative(platform);
