import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/vision_library.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/wheel_library.dart';

import '../sdk_downloads.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final target = buildTarget(code);
    requireDynamicLinking(code);
    // Flutter 3.44 reports a fixed iOS targetVersion of 13 here, independently
    // of Runner's deployment target. It cannot validate the app's minimum OS.
    // Our arm64 simulator binaries require iOS 14; see tool/IOS_SIMULATOR.md.
    final usePrebuilt = input.userDefines['prebuilt'];
    if (usePrebuilt != null && usePrebuilt is! bool) {
      throw const FormatException(
        'mediapipe_flutter_vision.prebuilt must be a boolean.',
      );
    }
    final selection =
        input.userDefines['tasks'] ?? ['face_detector', 'face_landmarker'];
    if (selection is! List ||
        selection.isEmpty ||
        selection.any((task) => !visionTasks.contains(task))) {
      throw FormatException(
        'mediapipe_flutter_vision.tasks must be a nonempty list of '
        '${visionTasks.join(', ')}.',
      );
    }
    output.dependencies.add(input.packageRoot.resolve('sdk_downloads.dart'));
    final tasks = selection.cast<String>().toSet();
    if (tasks.remove(sharedRuntimeTask)) {
      if (input.metadata['mediapipe_flutter_core']['tasks_runtime'] != true) {
        throw StateError(
          'Interactive Segmenter requires hooks.user_defines.'
          'mediapipe_flutter_core.tasks_runtime: true in the app pubspec. '
          'This bundles the shared modern runtime once for vision and text.',
        );
      }
      // Core's hook rejects targets its runtime table has no release for.
    }
    final wheelRelease = visionWheelReleases[target];
    if (wheelRelease != null && tasks.isNotEmpty) {
      final missing = tasks.difference(wheelRelease.tasks);
      if (missing.isNotEmpty) {
        throw UnsupportedError(
          'No validated $target runtime covers ${missing.join(', ')}. '
          'Available tasks: ${wheelRelease.tasks.join(', ')}.',
        );
      }
      final library = await downloadVisionWheel(
        wheelRelease,
        Directory.fromUri(input.outputDirectoryShared.resolve('$target/')),
      );
      // Dart rejects duplicate physical filenames across asset IDs. Preserve
      // the existing generated bindings with a distinct file per selected task.
      for (final task in tasks) {
        final suffix = target.startsWith('windows/') ? 'dll' : 'so';
        final bundled = await library.copy(
          File.fromUri(library.parent.uri.resolve('lib$task.$suffix')).path,
        );
        _addAsset(input, output, library: bundled, assetName: '$task.dylib');
      }
      return;
    }
    final published = visionRuntimeReleases.where(
      (release) => release.target == target,
    );
    final localOnly = localOnlyVisionTargets.contains(target);
    if (published.isEmpty && !localOnly && tasks.isNotEmpty) {
      throw UnsupportedError(
        'mediapipe_flutter_vision has no runtime for $target. Published '
        'targets: ${{...visionRuntimeReleases.map((r) => r.target), ...visionWheelReleases.keys}.join(', ')}; '
        'maintainer-build targets: ${localOnlyVisionTargets.join(', ')}.',
      );
    }
    final missing = tasks.where(
      (task) => !published.any((release) => release.tasks.contains(task)),
    );
    if (missing.isNotEmpty && !localOnly) {
      throw UnsupportedError(
        'No published $target runtime covers ${missing.join(', ')}. '
        'Tasks published for $target: '
        '${published.expand((r) => r.tasks).toSet().join(', ')}.',
      );
    }
    if (localOnly) {
      for (final task in tasks) {
        await _bundleLocalBuild(input, output, target: target, task: task);
      }
      return;
    }
    for (final release in published.where(
      (release) => release.tasks.any(tasks.contains),
    )) {
      await _bundleRelease(input, output, release: release, target: target);
    }
  });
}

/// Bundles a published release, or a maintainer's local source build of the
/// same task when one exists and `prebuilt: true` was not requested.
Future<void> _bundleRelease(
  BuildInput input,
  BuildOutputBuilder output, {
  required VisionRuntimeRelease release,
  required String target,
}) async {
  final local = Directory.fromUri(
    input.packageRoot.resolve(release.localBuildDirectory),
  );
  final archive = release.archive;
  final hasLocalBuild = await File.fromUri(
    local.uri.resolve(release.libraryName),
  ).exists();
  final File library;
  if (input.userDefines['prebuilt'] != true && hasLocalBuild) {
    // Maintainers can continue testing builds made by tool/build_native.py.
    // A normal dependency installation has no package-local build directory.
    library = await validateVisionLibrary(
      local,
      libraryName: release.libraryName,
      target: visionLibraryTarget(target),
    );
  } else if (archive == null) {
    throw StateError(
      'The ${release.release} runtime is not published yet, so it can only be '
      'served from a local source build. Run python3 tool/build_native.py in '
      'the vision package and omit prebuilt: true. Tasks it covers: '
      '${release.tasks.join(', ')}.',
    );
  } else {
    library = await downloadVisionLibrary(
      asset: archive,
      librarySha256: release.librarySha256,
      libraryName: release.libraryName,
      cache: Directory.fromUri(input.outputDirectoryShared.resolve('$target/')),
    );
  }
  _addAsset(input, output, library: library, assetName: release.assetName);
}

/// Bundles a task from a target that only has maintainer builds.
Future<void> _bundleLocalBuild(
  BuildInput input,
  BuildOutputBuilder output, {
  required String target,
  required String task,
}) async {
  final local = Directory.fromUri(
    input.packageRoot.resolve('build/native/$target/$task/'),
  );
  final libraryName = 'lib$task.dylib';
  if (input.userDefines['prebuilt'] == true ||
      !await File.fromUri(local.uri.resolve(libraryName)).exists()) {
    throw StateError(
      '$target runtimes are currently local development builds. '
      'Run python3 tool/build_ios_simulator.py in the vision package '
      'and omit prebuilt: true. No macOS library can substitute for '
      'a $target library.',
    );
  }
  final library = await validateVisionLibrary(
    local,
    libraryName: libraryName,
    target: visionLibraryTarget(target),
  );
  _addAsset(input, output, library: library, assetName: '$task.dylib');
}

void _addAsset(
  BuildInput input,
  BuildOutputBuilder output, {
  required File library,
  required String assetName,
}) {
  output.dependencies.add(library.uri);
  output.dependencies.add(library.parent.uri.resolve('manifest.json'));
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: assetName,
      linkMode: DynamicLoadingBundled(),
      file: library.uri,
    ),
  );
}
