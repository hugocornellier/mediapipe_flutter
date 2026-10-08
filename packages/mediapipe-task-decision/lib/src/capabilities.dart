/// Decision Maker's delegate support, queried without loading a model.
library;

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import 'decision_backend.dart' show decisionBackendFactory;

/// The release behind Decision Maker on every platform: Google's 1.1.0
/// wheels on the desktop and `@mediapipe/tasks-decision` 1.1.0 in browsers.
const decisionRuntimeVersion = '1.1.0';

/// Where Google's C library with Decision Maker exists: only in its desktop
/// Python wheels, which core's `wheelRuntimes` pins.
const decisionRuntimeTargets = <String, String?>{
  'macos/arm64': '14.0',
  'linux/x64': null,
  'windows/x64': null,
};

const _noLibrary =
    'Google publishes no C library with Decision Maker for this platform '
    'yet: only its desktop wheels have one. Run the task on macOS, Linux, '
    'Windows or in a browser.';

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
    "Google's desktop library runs Decision Maker on the CPU; this package "
    'has not validated its GPU path.';

const _noPlugin =
    'The MediaPipe Decision browser plugin did not register. Depend on '
    'mediapipe_decision as a Flutter plugin.';

String _noWebGpu(TaskPlatform platform) =>
    "Google's browser Decision Maker answers only on a hardware WebGPU "
    'adapter; without one it falls back to its CPU path, where every '
    'evaluation fails (upstream-issues.md UP-049). This browser has '
    '${platform.gpu ?? 'no WebGPU adapter'}.';

/// Query Decision Maker support on this platform without a model.
Future<TaskCapabilities> queryDecisionMakerCapabilities() async =>
    decisionMakerCapabilitiesForPlatform(await currentTaskPlatform());

/// Decision Maker support on [platform]: the CPU on Google's desktop wheel
/// library, and the GPU in browsers once the plugin registers, since
/// Google's browser runtime fails on the CPU (UP-049).
TaskCapabilities decisionMakerCapabilitiesForPlatform(TaskPlatform platform) {
  final web = platform.operatingSystem == 'web';
  return TaskCapabilities.onTargets(
    platform: platform,
    delegates: {
      Delegate.cpu: decisionRuntimeTargets,
      Delegate.gpu: {
        if (decisionBackendFactory != null && _hardwareWebGpu(platform))
          'web/unknown': null,
      },
    },
    unavailableReasons: {
      // Without a hardware adapter both delegates end on Google's CPU path.
      Delegate.cpu: !web
          ? _noLibrary
          : _hardwareWebGpu(platform)
          ? _browserCpu
          : _noWebGpu(platform),
      Delegate.gpu: web
          ? decisionBackendFactory == null
                ? _noPlugin
                : _noWebGpu(platform)
          : decisionRuntimeTargets.containsKey(platform.target)
          ? _desktopGpu
          : _noLibrary,
    },
    runtimeVersion: decisionRuntimeVersion,
  );
}
