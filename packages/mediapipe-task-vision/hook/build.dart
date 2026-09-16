import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
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
      for (final assetName in _assetNames(tasks)) {
        final suffix = target.startsWith('windows/') ? 'dll' : 'so';
        final stem = assetName.substring(0, assetName.length - '.dylib'.length);
        final bundled = File.fromUri(
          library.parent.uri.resolve('lib$stem.$suffix'),
        );
        if (!await bundled.exists() ||
            (await sha256.bind(bundled.openRead()).first).toString() !=
                wheelRelease.librarySha256) {
          await library.copy(bundled.path);
        }
        _addAsset(input, output, library: bundled, assetName: assetName);
      }
      return;
    }
    final published = visionRuntimeReleases.where(
      (release) => release.target == target,
    );
    if (published.isEmpty && tasks.isNotEmpty) {
      throw UnsupportedError(
        'mediapipe_flutter_vision has no runtime for $target. Published '
        'targets: ${{...visionRuntimeReleases.map((r) => r.target), ...visionWheelReleases.keys}.join(', ')}.',
      );
    }
    final missing = tasks.where(
      (task) => !published.any((release) => release.tasks.contains(task)),
    );
    if (missing.isNotEmpty) {
      throw UnsupportedError(
        'No published $target runtime covers ${missing.join(', ')}. '
        'Tasks published for $target: '
        '${published.expand((r) => r.tasks).toSet().join(', ')}.',
      );
    }
    for (final release in published.where(
      (release) => release.tasks.any(tasks.contains),
    )) {
      await _bundleRelease(
        input,
        output,
        release: release,
        target: target,
        tasks: tasks.intersection(release.tasks),
      );
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
  required Set<String> tasks,
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
      target: visionLibraryTarget(target),
    );
  }
  await _bundleAliases(input, output, library: library, tasks: tasks);
}

/// Asset IDs are compile-time constants in the generated bindings: each face
/// binding set names its own library and every other task shares vision.dylib.
/// Dart also rejects duplicate physical filenames across asset IDs, so one
/// runtime serving several IDs is copied once per name.
Set<String> _assetNames(Set<String> tasks) => {
  for (final task in tasks)
    if (task == 'face_detector' || task == 'face_landmarker')
      '$task.dylib'
    else
      'vision.dylib',
};

Future<void> _bundleAliases(
  BuildInput input,
  BuildOutputBuilder output, {
  required File library,
  required Set<String> tasks,
}) async {
  final digest = (await sha256.bind(library.openRead()).first).toString();
  for (final assetName in _assetNames(tasks)) {
    final stem = assetName.substring(0, assetName.length - '.dylib'.length);
    final bundled = File.fromUri(library.parent.uri.resolve('lib$stem.dylib'));
    if (!await bundled.exists() ||
        (await sha256.bind(bundled.openRead()).first).toString() != digest) {
      await library.copy(bundled.path);
    }
    _addAsset(input, output, library: bundled, assetName: assetName);
  }
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
