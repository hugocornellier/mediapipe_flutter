/// The retrieval tasks' delegate support, queried without loading a model.
library;

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import 'retrieval_backend.dart' show retrievalBackendFactory;

/// The release of `@mediapipe/tasks-retrieval` that `assets/runtime.json`
/// pins for browsers (`tool/check_repository.py` checks the two agree).
const _browserRuntimeVersion = '1.1.0';

/// The release behind both tasks on [platform]: Google's per-family
/// retrieval library natively (its 1.1.1 build of October 9, 2026) and the
/// browser runtime in browsers.
String _runtimeVersionOn(TaskPlatform platform) =>
    platform.operatingSystem == 'web'
    ? _browserRuntimeVersion
    : tasksRuntimeVersionOn(platform);

/// Where Google's retrieval library runs: core's shared targets, which
/// Google's per-family build covers as its vision, text and audio libraries
/// do.
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

/// Why both tasks are unavailable in WebKit (UP-054).
const embeddingGemma2WebKitUnavailable =
    "In WebKit, the engine of Safari and of every browser on iOS, Google's "
    'browser Universal Embedder (@mediapipe/tasks-retrieval 1.1.0) returns '
    'zeros for every input with both EmbeddingGemma 2 models, so no document '
    'matches any query (upstream-issues.md UP-054). Use a Chromium browser.';

/// Both tasks' support on [platform]: the CPU on Google's retrieval library
/// natively, and the GPU in browsers once the plugin registers, on a hardware
/// WebGPU adapter only, since Google's browser runtime has no CPU path, and
/// not in WebKit, where it embeds everything as zeros (UP-054).
TaskCapabilities _capabilities(TaskPlatform platform) {
  final web = platform.operatingSystem == 'web';
  final browserRuns =
      retrievalBackendFactory != null && _hardwareWebGpu(platform);
  final webKit = platform.browserEngine == BrowserEngine.webkit;
  return TaskCapabilities.onTargets(
    platform: platform,
    delegates: {
      Delegate.cpu: retrievalRuntimeTargets,
      Delegate.gpu: {if (browserRuns && !webKit) 'web/unknown': null},
    },
    unavailableReasons: {
      // Without a hardware adapter both delegates end on Google's WebGPU check.
      Delegate.cpu: !web
          ? _desktopGpu
          : browserRuns && webKit
          ? embeddingGemma2WebKitUnavailable
          : _hardwareWebGpu(platform)
          ? _browserCpu
          : _noWebGpu(platform),
      Delegate.gpu: web
          ? retrievalBackendFactory == null
                ? _noPlugin
                : browserRuns && webKit
                ? embeddingGemma2WebKitUnavailable
                : _noWebGpu(platform)
          : _desktopGpu,
    },
    runtimeVersion: _runtimeVersionOn(platform),
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
