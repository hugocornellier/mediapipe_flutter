/// Query the modern text tasks' support without loading a model.
library;

import 'package:mediapipe_core/capabilities.dart';

import 'src/interface/embedding_gemma_types.dart';
import 'src/text_task_backend.dart' show textTaskBackendFactory;

export 'package:mediapipe_core/capabilities.dart'
    show TaskCapabilities, TaskPlatform;

export 'src/interface/embedding_gemma_types.dart' show TextDelegate;

/// Modern text tasks supplied by the official MediaPipe 1.0.1 runtime.
enum TextTask {
  /// EmbeddingGemma 300M.
  embeddingGemma,

  /// Proofreader 200M.
  proofreader,

  /// Summarizer 200M.
  summarizer,
}

TaskCapabilities<TextDelegate> _classicCapabilities(TaskPlatform platform) =>
    TaskCapabilities.cpuOnTargets(
      platform: platform,
      cpu: TextDelegate.cpu,
      gpu: TextDelegate.gpu,
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

/// Query Text Classifier delegates and reasons without loading a model.
Future<TaskCapabilities<TextDelegate>>
queryTextClassifierCapabilities() async =>
    _classicCapabilities(await currentTaskPlatform());

/// Query Text Embedder delegates and reasons without loading a model.
Future<TaskCapabilities<TextDelegate>> queryTextEmbedderCapabilities() async =>
    _classicCapabilities(await currentTaskPlatform());

/// Query Language Detector delegates and reasons without loading a model.
Future<TaskCapabilities<TextDelegate>>
queryLanguageDetectorCapabilities() async =>
    _classicCapabilities(await currentTaskPlatform());

/// Query EmbeddingGemma delegates and reasons without loading a model.
Future<TaskCapabilities<TextDelegate>> queryEmbeddingGemmaCapabilities() =>
    queryTextTaskCapabilities(TextTask.embeddingGemma);

/// Query Proofreader delegates and reasons without loading a model.
Future<TaskCapabilities<TextDelegate>> queryTextProofreaderCapabilities() =>
    queryTextTaskCapabilities(TextTask.proofreader);

/// Query Summarizer delegates and reasons without loading a model.
Future<TaskCapabilities<TextDelegate>> queryTextSummarizerCapabilities() =>
    queryTextTaskCapabilities(TextTask.summarizer);

/// Describe validated package support on this process platform.
///
/// Does not load a model or verify the app's native-asset opt-in. Task creation
/// remains responsible for reporting invalid models and missing runtime assets.
Future<TaskCapabilities<TextDelegate>> queryTextTaskCapabilities(
  TextTask task,
) async => textTaskCapabilitiesForPlatform(task, await currentTaskPlatform());

/// Evaluate package support for a platform snapshot, e.g. in a settings UI test.
TaskCapabilities<TextDelegate> textTaskCapabilitiesForPlatform(
  TextTask task,
  TaskPlatform platform,
) => TaskCapabilities.macosCpu(
  platform: platform,
  cpu: TextDelegate.cpu,
  gpu: TextDelegate.gpu,
  gpuUnavailableReason: switch (task) {
    TextTask.embeddingGemma =>
      "Google's macOS EmbeddingGemma Metal interpreter fails during creation "
          '(observed with MediaPipe 1.0.1). CPU is supported.',
    TextTask.proofreader ||
    TextTask.summarizer => "Google's task accepts only the CPU delegate.",
  },
);
