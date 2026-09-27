import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_core/src/native_assets/tasks_runtime.dart';

Future<void> main(List<String> arguments) => build(arguments, (
  input,
  output,
) async {
  final enabled = input.userDefines['tasks_runtime'] ?? false;
  if (enabled is! bool) {
    throw const FormatException(
      'mediapipe_flutter_core.tasks_runtime must be a boolean.',
    );
  }
  final useMacosVisionRuntime =
      input.userDefines['use_macos_vision_runtime'] ?? false;
  if (useMacosVisionRuntime is! bool) {
    throw const FormatException(
      'mediapipe_flutter_core.use_macos_vision_runtime must be a boolean.',
    );
  }
  if (useMacosVisionRuntime && !enabled) {
    throw StateError('use_macos_vision_runtime requires tasks_runtime: true.');
  }
  output.metadata['tasks_runtime'] = enabled;
  if (!enabled || !input.config.buildCodeAssets) return;
  final code = input.config.code;
  final target = buildTarget(code);
  if (useMacosVisionRuntime) {
    if (target != 'macos/arm64') {
      throw UnsupportedError(
        'use_macos_vision_runtime requires macos/arm64, not $target.',
      );
    }
    requireDynamicLinking(code);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: tasksRuntimeAssetName,
        linkMode: DynamicLoadingSystem(
          Uri(path: '@rpath/vision.framework/vision'),
        ),
      ),
    );
    output.metadata['use_macos_vision_runtime'] = true;
    return;
  }
  if (tasksRuntimeIosTargets.contains(target)) {
    // Google's iOS SDK implements every task in one MediaPipeTasksCommon,
    // so the text and audio tasks run in the adapter the vision package
    // builds over it, which bundles that copy once for all tasks.
    requireDynamicLinking(code);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: tasksRuntimeAssetName,
        linkMode: DynamicLoadingSystem(Uri(path: tasksRuntimeIosAdapter)),
      ),
    );
    return;
  }
  final wheelRuntime = tasksWheelRuntimes[target];
  if (wheelRuntime != null) {
    requireDynamicLinking(code);
    final library = await downloadOfficialWheelLibrary(
      wheelRuntime,
      Directory.fromUri(
        input.outputDirectoryShared.resolve(
          '$target/wheel-${wheelRuntime.version}/',
        ),
      ),
    );
    output.dependencies.add(library.uri);
    output.dependencies.add(library.parent.uri.resolve('manifest.json'));
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: tasksRuntimeAssetName,
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
    // The vision hook maps its assets onto this copy when it sees it.
    output.metadata['tasks_runtime_library'] = {
      'name': wheelRuntime.libraryName,
      'sha256': wheelRuntime.librarySha256,
    };
    return;
  }
  final release = requireTasksRuntimeRelease(target);
  requireDynamicLinking(code);
  final library = await downloadTasksRuntime(
    release: release,
    cache: Directory.fromUri(
      input.outputDirectoryShared.resolve(
        '$target/tasks-$tasksRuntimeVersion/',
      ),
    ),
  );
  output.dependencies.add(library.uri);
  output.dependencies.add(library.parent.uri.resolve('manifest.json'));
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: tasksRuntimeAssetName,
      linkMode: DynamicLoadingBundled(),
      file: library.uri,
    ),
  );
});
