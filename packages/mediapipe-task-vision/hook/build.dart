import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/android_library.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/ios_sdk.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/vision_library.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/wheel_library.dart';

import '../sdk_downloads.dart';

/// Tasks the Android Flutter plugin serves through Google's official SDK.
const officialAndroidTasks = {
  'face_detector',
  'face_landmarker',
  'gesture_recognizer',
  'hand_landmarker',
  'holistic_landmarker',
  'image_classifier',
  'image_embedder',
  'image_segmenter',
  'interactive_segmenter',
  'object_detector',
  'pose_landmarker',
};

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final target = buildTarget(code);
    requireDynamicLinking(code);
    // Flutter reports a fixed iOS targetVersion here (13 in 3.44, 15 in 3.47),
    // independently of Runner's deployment target, so it cannot validate the
    // app's minimum OS.
    // Our arm64 simulator binaries require iOS 14; see tool/IOS_SIMULATOR.md.
    final usePrebuilt = input.userDefines['prebuilt'];
    if (usePrebuilt != null && usePrebuilt is! bool) {
      throw const FormatException(
        'mediapipe_flutter_vision.prebuilt must be a boolean.',
      );
    }
    final useOfficialMacosLandmarks =
        input.userDefines['official_macos_landmark_tasks'];
    if (useOfficialMacosLandmarks != null &&
        useOfficialMacosLandmarks is! bool) {
      throw const FormatException(
        'mediapipe_flutter_vision.official_macos_landmark_tasks must be a '
        'boolean.',
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
    final officialIosSdk = input.userDefines['official_ios_sdk'];
    if (officialIosSdk != null && officialIosSdk is! bool) {
      throw const FormatException('official_ios_sdk must be a boolean.');
    }
    final officialAndroidSdk = input.userDefines['official_android_sdk'];
    if (officialAndroidSdk != null && officialAndroidSdk is! bool) {
      throw const FormatException('official_android_sdk must be a boolean.');
    }
    // Google's SDK is the default on the Android targets it is validated on
    // (arm64 phones, the x86_64 emulator): the mediapipe_flutter_vision_android
    // plugin serves every task there. `official_android_sdk: false` selects
    // the source-built face runtime instead.
    final useAndroidSdk =
        officialAndroidSdk as bool? ??
        ((target == 'android/arm64' || target == 'android/x64') &&
            officialIosSdk != true &&
            useOfficialMacosLandmarks != true);
    if (useAndroidSdk) {
      if (!target.startsWith('android/') ||
          tasks.isEmpty ||
          !officialAndroidTasks.containsAll(tasks) ||
          officialIosSdk == true ||
          useOfficialMacosLandmarks == true) {
        throw UnsupportedError(
          'official_android_sdk requires Android, only '
          '${officialAndroidTasks.join(' and ')}, and the '
          'mediapipe_flutter_vision_android Flutter plugin.',
        );
      }
      // The Flutter plugin owns Google's Java/JNI SDK. These unused C bindings
      // remain lazy process lookups rather than bundling a second graph registry.
      for (final name in {...tasks.map((t) => '$t.dylib'), 'vision.dylib'}) {
        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: name,
            linkMode: LookupInProcess(),
          ),
        );
      }
      output.metadata['official_android_sdk'] = '1.0.0';
      return;
    }
    if (officialIosSdk == true) {
      if (useOfficialMacosLandmarks == true) {
        throw StateError('Select only one official platform SDK.');
      }
      await buildOfficialIosSdk(input, output, tasks: tasks);
      return;
    }
    // Linux's official wheel library exports the stateful API itself, so the
    // task binds the vision asset there and needs no shared runtime.
    final wheelServesSharedTask =
        visionWheelReleases[target]?.tasks.contains(sharedRuntimeTask) ?? false;
    if (!wheelServesSharedTask && tasks.remove(sharedRuntimeTask)) {
      if (input.metadata['mediapipe_flutter_core']['tasks_runtime'] != true) {
        throw StateError(
          'Interactive Segmenter requires hooks.user_defines.'
          'mediapipe_flutter_core.tasks_runtime: true in the app pubspec. '
          'This bundles the shared modern runtime once for vision and text.',
        );
      }
      // Core's hook rejects targets its runtime table has no release for.
    }
    if (useOfficialMacosLandmarks == true) {
      if (target != officialMacosLandmarkRuntime.target) {
        throw UnsupportedError(
          'The official macOS landmark runtime only supports '
          '${officialMacosLandmarkRuntime.target}, not $target.',
        );
      }
      final validated = tasks.intersection(officialMacosLandmarkRuntime.tasks);
      if (validated.isEmpty) {
        throw StateError(
          'official_macos_landmark_tasks requires at least one of '
          '${officialMacosLandmarkRuntime.tasks.join(', ')} in tasks.',
        );
      }
      tasks.removeAll(validated);
      // All non-face task bindings share one `vision.dylib` asset ID. Once the
      // official monolith owns that ID for Hand or Pose, it must also serve any
      // other selected task using the ID; registering the source monolith too
      // would produce a duplicate native asset. These extra tasks remain
      // unvalidated and are deliberately absent from the release's task set.
      final aliases = _assetNames(validated);
      final sharingSelectedAlias = {
        for (final task in tasks)
          if (_assetNames({task}).any(aliases.contains)) task,
      };
      tasks.removeAll(sharingSelectedAlias);
      await _bundleRelease(
        input,
        output,
        release: officialMacosLandmarkRuntime,
        target: target,
        tasks: {...validated, ...sharingSelectedAlias},
        oneImage: true,
      );
      output.metadata['official_macos_landmark_tasks'] = validated.toList()
        ..sort();
    }
    if (target == 'android/arm64' || target == 'android/x64') {
      if (tasks.isNotEmpty) {
        await _bundleAndroid(input, output, target: target, tasks: tasks);
      }
      return;
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
      // Bundle Google's monolith once. Loading renamed copies for face and
      // other vision tasks registers the same graphs twice and aborts.
      _addAsset(input, output, library: library, assetName: 'vision.dylib');
      for (final assetName in _assetNames(tasks).difference({'vision.dylib'})) {
        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: assetName,
            linkMode: DynamicLoadingSystem(Uri.file(wheelRelease.libraryName)),
          ),
        );
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
  bool oneImage = false,
}) async {
  final local = Directory.fromUri(
    input.packageRoot.resolve(release.localBuildDirectory),
  );
  final archive = release.archive;
  final hasLocalBuild = await File.fromUri(
    local.uri.resolve(release.libraryName),
  ).exists();
  final File library;
  if (hasLocalBuild &&
      (release.officialWheel != null ||
          input.userDefines['prebuilt'] != true)) {
    // Maintainers can continue testing builds made by tool/build_native.py.
    // A normal dependency installation has no package-local build directory.
    library = await validateVisionLibrary(
      local,
      expectedSha256: release.officialWheel == null
          ? null
          : release.librarySha256,
      libraryName: release.libraryName,
      target: visionLibraryTarget(target),
      officialWheel: release.officialWheel,
    );
  } else if (archive == null) {
    if (release.officialWheel != null) {
      throw StateError(
        'The ${release.release} runtime must be prepared locally. Run python3 '
        'tool/prepare_official_macos_landmark_runtime.py in the vision package.',
      );
    }
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
      officialWheel: release.officialWheel,
    );
  }
  await _bundleAliases(
    input,
    output,
    library: library,
    tasks: tasks,
    oneImage: oneImage,
  );
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

Future<void> _bundleAndroid(
  BuildInput input,
  BuildOutputBuilder output, {
  required String target,
  required Set<String> tasks,
}) async {
  final missing = tasks.difference({'face_detector', 'face_landmarker'});
  if (missing.isNotEmpty) {
    throw UnsupportedError(
      'Android face CI does not validate ${missing.join(', ')}.',
    );
  }
  final abi = target == 'android/arm64' ? 'arm64-v8a' : 'x86_64';
  final local = Directory.fromUri(
    input.packageRoot.resolve('build/native/android/$abi/'),
  );
  if (input.userDefines['prebuilt'] == true ||
      !await File.fromUri(local.uri.resolve('libmediapipe.so')).exists()) {
    throw StateError(
      'Android runtimes require a local source build. '
      'Run tool/build_android.py --ndk <path> --abi $abi and omit prebuilt: true. '
      'No Android public archive is pinned.',
    );
  }
  final libraries = await validateAndroidVisionLibrary(
    local,
    abi: abi,
    targetApi: input.config.code.android.targetNdkApi,
  );
  await _bundleAliases(
    input,
    output,
    library: libraries.first,
    tasks: tasks,
    suffix: 'so',
  );
  for (final dependency in libraries.skip(1)) {
    _addAsset(
      input,
      output,
      library: dependency,
      assetName: dependency.uri.pathSegments.last,
    );
  }
}

/// With [oneImage], a runtime that serves the shared vision asset is bundled
/// once, as that asset only. Google's macOS monolith registers its graphs in a
/// registry that dyld shares between loaded images, so a second copy for the
/// face asset aborts on its first duplicate registration; Face Landmarker then
/// calls the same functions through the shared asset
/// (lib/src/io/face_landmarker_api.dart).
Future<void> _bundleAliases(
  BuildInput input,
  BuildOutputBuilder output, {
  required File library,
  required Set<String> tasks,
  String suffix = 'dylib',
  bool oneImage = false,
}) async {
  final digest = (await sha256.bind(library.openRead()).first).toString();
  var names = _assetNames(tasks);
  if (oneImage && names.contains('vision.dylib')) names = {'vision.dylib'};
  for (final assetName in names) {
    final stem = assetName.substring(0, assetName.length - '.dylib'.length);
    final bundled = File.fromUri(
      library.parent.uri.resolve('lib$stem.$suffix'),
    );
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
