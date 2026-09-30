import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_core/src/native_assets/ios_sdk.dart';
import 'package:mediapipe_core/src/native_assets/tasks_runtime.dart';

/// Bundles Google's MediaPipe engine once per app for every task family.
///
/// `hooks.user_defines.mediapipe_core.tasks_runtime` is optional: it
/// defaults to on where the engine costs nothing extra (iOS, Linux x64,
/// Windows x64) and off on macOS, where it is 95 MB. Like every setting here,
/// it is harmless on targets it does not apply to, since an app's
/// `user_defines` cover all of its platforms: Android and browsers run
/// Google's own SDKs through the family plugins instead.
Future<void> main(List<String> arguments) => build(arguments, (
  input,
  output,
) async {
  final requested = input.userDefines['tasks_runtime'];
  if (requested != null && requested is! bool) {
    throw const FormatException(
      'mediapipe_core.tasks_runtime must be a boolean.',
    );
  }
  if (input.userDefines['use_macos_vision_runtime'] != null) {
    throw const FormatException(
      'mediapipe_core.use_macos_vision_runtime was removed: core now '
      "bundles Google's macOS engine and the vision tasks use it. Delete the "
      'key; set tasks_runtime: true instead.',
    );
  }
  // Family hooks download through the same source (hookAssetSource).
  final source = hookAssetSource(input);
  if (source != null) output.metadata['asset_source'] = source;
  if (!input.config.buildCodeAssets) {
    output.metadata['tasks_runtime'] = false;
    return;
  }
  final code = input.config.code;
  final target = buildTarget(code);
  final enabled =
      hasTasksRuntime(target) &&
      (requested as bool? ?? tasksRuntimeEnabledByDefault(target));
  output.metadata['tasks_runtime'] = enabled;
  if (!enabled) return;
  requireDynamicLinking(code);
  if (tasksRuntimeIosTargets.contains(target)) {
    // Google's iOS SDK implements every task in one MediaPipeTasksCommon, so
    // core builds the one adapter every family binds.
    await buildOfficialIosSdk(input, output);
    return;
  }
  final wheelRuntime = tasksWheelRuntimes[target];
  if (wheelRuntime != null) {
    final library = await downloadOfficialWheelLibrary(
      wheelRuntime,
      Directory.fromUri(
        input.outputDirectoryShared.resolve(
          '$target/wheel-${wheelRuntime.version}/',
        ),
      ),
      source: source,
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
    // The vision face assets alias this copy by its file name.
    output.metadata['tasks_runtime_library'] = {
      'name': wheelRuntime.libraryName,
      'sha256': wheelRuntime.librarySha256,
    };
    output.metadata['tasks_runtime_version'] = wheelRuntime.version;
    return;
  }
  final release = requireTasksRuntimeRelease(target);
  final library = await downloadTasksRuntime(
    release: release,
    cache: Directory.fromUri(
      input.outputDirectoryShared.resolve('$target/tasks-${release.version}/'),
    ),
    source: source,
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
  output.metadata['tasks_runtime_version'] = release.version;
});
