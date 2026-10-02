/// Per-task delegate support, queried without loading a model.
library;

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import '../models.dart' show TextModels;
import 'text_task_backend.dart' show textTaskBackendFactory;

/// The classic tasks run on CPU wherever core's runtime or a registered
/// platform backend serves them.
TaskCapabilities _classic(TaskPlatform platform) =>
    TaskCapabilities.cpuOnTargets(
      platform: platform,
      gpuUnavailableReason: 'The official classic text tasks run on CPU only.',
      runtimeVersion: tasksRuntimeVersionOn(platform),
      targets: {
        ...tasksRuntimeTargets,
        if (textTaskBackendFactory != null) ...{
          'web/unknown': null,
          'android/arm64': null,
          'android/x64': null,
        },
      },
    );

/// Query Text Classifier support on this platform without a model.
Future<TaskCapabilities> queryTextClassifierCapabilities() async =>
    textClassifierCapabilitiesForPlatform(await currentTaskPlatform());

/// Text Classifier support on [platform]: CPU on core's runtime and the
/// registered browser and Android backends.
TaskCapabilities textClassifierCapabilitiesForPlatform(TaskPlatform platform) =>
    _classic(platform);

/// Query Language Detector support on this platform without a model.
Future<TaskCapabilities> queryLanguageDetectorCapabilities() async =>
    languageDetectorCapabilitiesForPlatform(await currentTaskPlatform());

/// Language Detector support on [platform], as for the Text Classifier.
TaskCapabilities languageDetectorCapabilitiesForPlatform(
  TaskPlatform platform,
) => _classic(platform);

/// Query Text Embedder support on this platform for [model]: pass
/// `TextModels.embeddingGemma` to learn where EmbeddingGemma runs.
Future<TaskCapabilities> queryTextEmbedderCapabilities([
  DownloadAsset? model,
]) async => textEmbedderCapabilitiesForPlatform(
  await currentTaskPlatform(),
  model: model,
);

/// Text Embedder support on [platform]: the classic embedders as for the
/// Text Classifier, and EmbeddingGemma on Google's macOS engine's CPU only.
TaskCapabilities textEmbedderCapabilitiesForPlatform(
  TaskPlatform platform, {
  DownloadAsset? model,
}) => model?.sha256 == TextModels.embeddingGemma.sha256
    ? TaskCapabilities.macosCpu(
        platform: platform,
        gpuUnavailableReason:
            "Google's macOS EmbeddingGemma Metal interpreter fails during "
            'creation (observed with MediaPipe 1.0.1). CPU is supported.',
      )
    : _classic(platform);

/// Query Proofreader support on this platform without a model.
Future<TaskCapabilities> queryTextProofreaderCapabilities() async =>
    textProofreaderCapabilitiesForPlatform(await currentTaskPlatform());

/// Proofreader support on [platform]: Google's macOS engine's CPU only.
TaskCapabilities textProofreaderCapabilitiesForPlatform(
  TaskPlatform platform,
) => TaskCapabilities.macosCpu(
  platform: platform,
  gpuUnavailableReason: "Google's task accepts only the CPU delegate.",
);

/// Query Summarizer support on this platform without a model.
Future<TaskCapabilities> queryTextSummarizerCapabilities() async =>
    textSummarizerCapabilitiesForPlatform(await currentTaskPlatform());

/// Summarizer support on [platform]: Google's macOS engine's CPU only.
TaskCapabilities textSummarizerCapabilitiesForPlatform(TaskPlatform platform) =>
    TaskCapabilities.macosCpu(
      platform: platform,
      gpuUnavailableReason: "Google's task accepts only the CPU delegate.",
    );
