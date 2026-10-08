/// The retrieval tasks' delegate support, queried without loading a model.
library;

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import 'retrieval_backend.dart' show retrievalBackendFactory;

/// The release behind both tasks on every platform: Google's per-family
/// retrieval library natively and `@mediapipe/tasks-retrieval` in browsers,
/// both MediaPipe 1.1.0.
const retrievalRuntimeVersion = '1.1.0';

/// Where Google's retrieval library runs: core's shared targets, which
/// Google's delivery of October 8, 2026 covers as its vision, text and audio
/// libraries do.
const retrievalRuntimeTargets = tasksRuntimeTargets;

const _gpu =
    "Google's retrieval tasks run on the CPU; this package has not validated "
    'a GPU path.';

/// CPU wherever Google's retrieval library or, in browsers, its JavaScript
/// runtime serves the tasks.
TaskCapabilities _onEveryRuntime(TaskPlatform platform) =>
    TaskCapabilities.cpuOnTargets(
      platform: platform,
      gpuUnavailableReason: _gpu,
      runtimeVersion: retrievalRuntimeVersion,
      targets: {
        ...retrievalRuntimeTargets,
        if (retrievalBackendFactory != null) 'web/unknown': null,
      },
    );

/// Query Universal Embedder support on this platform without a model.
Future<TaskCapabilities> queryUniversalEmbedderCapabilities() async =>
    universalEmbedderCapabilitiesForPlatform(await currentTaskPlatform());

/// Universal Embedder support on [platform]: the CPU on Google's retrieval
/// library and, once the plugin registers, in browsers.
TaskCapabilities universalEmbedderCapabilitiesForPlatform(
  TaskPlatform platform,
) => _onEveryRuntime(platform);

/// Query Semantic Retriever support on this platform without a model.
Future<TaskCapabilities> querySemanticRetrieverCapabilities() async =>
    semanticRetrieverCapabilitiesForPlatform(await currentTaskPlatform());

/// Semantic Retriever support on [platform], as for the embedder it runs on.
TaskCapabilities semanticRetrieverCapabilitiesForPlatform(
  TaskPlatform platform,
) => _onEveryRuntime(platform);
