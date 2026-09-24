/// Query the modern text tasks' support without loading a model.
library;

import 'package:mediapipe_flutter_core/capabilities.dart';

import 'src/interface/embedding_gemma_types.dart';

export 'package:mediapipe_flutter_core/capabilities.dart'
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
      'The official MediaPipe 1.0.1 macOS EmbeddingGemma Metal interpreter '
          'fails during creation. CPU is supported.',
    TextTask.proofreader || TextTask.summarizer =>
      'The official MediaPipe 1.0.1 task accepts only the CPU delegate.',
  },
);
