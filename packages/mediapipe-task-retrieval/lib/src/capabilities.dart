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

/// How the web plugin names a WebGPU adapter in `TaskPlatform.gpu`.
const webGpuAdapterPrefix = 'WebGPU';

/// The adapters Google's runtime refuses to run on, by Google's own rule.
final _softwareAdapter = RegExp(
  r'fallback|swiftshader|llvmpipe|software|lavapipe',
  caseSensitive: false,
);

/// Whether [platform] names a hardware WebGPU adapter, the only place
/// Google's browser Universal Embedder runs (UP-052).
bool _hardwareWebGpu(TaskPlatform platform) => switch (platform.gpu) {
  final gpu? =>
    gpu.startsWith(webGpuAdapterPrefix) && !_softwareAdapter.hasMatch(gpu),
  null => false,
};

const _desktopGpu =
    "Google's retrieval library runs the tasks on the CPU; this package has "
    'not validated a GPU path.';

const _noPlugin =
    'The MediaPipe Retrieval browser plugin did not register. Depend on '
    'mediapipe_retrieval as a Flutter plugin.';

/// Google's browser Universal Embedder creates a WebGPU device for itself
/// and has no CPU path (upstream-issues.md UP-052).
const _browserCpu =
    "Google's browser Universal Embedder (@mediapipe/tasks-retrieval 1.1.0) "
    'runs on a WebGPU device only (upstream-issues.md UP-052). Use '
    'Delegate.gpu.';

String _noWebGpu(TaskPlatform platform) =>
    "Google's browser Universal Embedder runs only on a hardware WebGPU "
    'adapter: it creates a WebGPU device for itself and refuses a software '
    'one (upstream-issues.md UP-052). This browser has '
    '${platform.gpu ?? 'no WebGPU adapter'}.';

/// Both tasks' support on [platform]: the CPU on Google's retrieval library
/// natively, and the GPU in browsers once the plugin registers, on a hardware
/// WebGPU adapter only, since Google's browser runtime has no CPU path.
TaskCapabilities _capabilities(TaskPlatform platform) {
  final web = platform.operatingSystem == 'web';
  return TaskCapabilities.onTargets(
    platform: platform,
    delegates: {
      Delegate.cpu: retrievalRuntimeTargets,
      Delegate.gpu: {
        if (retrievalBackendFactory != null && _hardwareWebGpu(platform))
          'web/unknown': null,
      },
    },
    unavailableReasons: {
      // Without a hardware adapter both delegates end on Google's WebGPU check.
      Delegate.cpu: !web
          ? _desktopGpu
          : _hardwareWebGpu(platform)
          ? _browserCpu
          : _noWebGpu(platform),
      Delegate.gpu: web
          ? retrievalBackendFactory == null
                ? _noPlugin
                : _noWebGpu(platform)
          : _desktopGpu,
    },
    runtimeVersion: retrievalRuntimeVersion,
  );
}

/// Query Universal Embedder support on this platform without a model.
Future<TaskCapabilities> queryUniversalEmbedderCapabilities() async =>
    universalEmbedderCapabilitiesForPlatform(await currentTaskPlatform());

/// Universal Embedder support on [platform]: the CPU on Google's retrieval
/// library, and in browsers the GPU on a hardware WebGPU adapter.
TaskCapabilities universalEmbedderCapabilitiesForPlatform(
  TaskPlatform platform,
) => _capabilities(platform);

/// Query Semantic Retriever support on this platform without a model.
Future<TaskCapabilities> querySemanticRetrieverCapabilities() async =>
    semanticRetrieverCapabilitiesForPlatform(await currentTaskPlatform());

/// Semantic Retriever support on [platform], as for the embedder it runs on.
TaskCapabilities semanticRetrieverCapabilitiesForPlatform(
  TaskPlatform platform,
) => _capabilities(platform);
