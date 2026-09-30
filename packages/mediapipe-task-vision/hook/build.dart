import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_core/src/native_assets/ios_sdk.dart';
import 'package:mediapipe_core/src/native_assets/tasks_runtime.dart';
import 'package:mediapipe_vision/src/native_assets/android_library.dart';
import 'package:mediapipe_vision/src/native_assets/vision_library.dart';

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

/// The two tasks whose bindings name their own assets. Every other task binds
/// Google's engine through the one asset mediapipe_core bundles.
const _faceTasks = {'face_detector', 'face_landmarker'};

/// Bundles what the selected vision tasks need beyond core's engine.
///
/// Google's MediaPipe engine is mediapipe_core's: vision, text and
/// audio all bind its one asset, so an app loads one copy. This hook adds only
/// the face runtimes the package builds from source (small macOS libraries,
/// and the iOS and Android opt-outs) and maps the face assets elsewhere.
/// Settings that name one platform are ignored on the others, since an app's
/// `user_defines` cover all of its targets.
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
    _optionalBool(input, 'prebuilt');
    if (input.userDefines['official_macos_landmark_tasks'] != null) {
      throw const FormatException(
        'mediapipe_vision.official_macos_landmark_tasks was removed: '
        "on macOS every task except the two face tasks runs on Google's "
        'engine, which mediapipe_core bundles. Delete the key and set '
        'hooks.user_defines.mediapipe_core.tasks_runtime: true.',
      );
    }
    final selection =
        input.userDefines['tasks'] ?? ['face_detector', 'face_landmarker'];
    if (selection is! List ||
        selection.isEmpty ||
        selection.any((task) => !visionTasks.contains(task))) {
      throw FormatException(
        'mediapipe_vision.tasks must be a nonempty list of '
        '${visionTasks.join(', ')}.',
      );
    }
    output.dependencies.add(input.packageRoot.resolve('sdk_downloads.dart'));
    var tasks = selection.cast<String>().toSet();
    final officialIosSdk = _optionalBool(input, 'official_ios_sdk');
    final officialAndroidSdk = _optionalBool(input, 'official_android_sdk');
    final core = input.metadata['mediapipe_core'];
    final coreRuntime = core['tasks_runtime'] == true;

    if (target == 'android/arm64' || target == 'android/x64') {
      // Google's SDK is the default on the Android targets it is validated on
      // (arm64 phones, the x86_64 emulator): the mediapipe_vision
      // plugin serves every task there. `official_android_sdk: false`
      // selects the source-built face runtime instead.
      if (officialAndroidSdk ?? true) {
        final missing = tasks.difference(officialAndroidTasks);
        if (missing.isNotEmpty) {
          throw UnsupportedError(
            "Google's Android SDK, which the mediapipe_vision plugin "
            'runs, serves ${officialAndroidTasks.join(', ')}; not '
            '${missing.join(', ')}.',
          );
        }
        // The plugin owns Google's Java/JNI SDK. The face tasks' C bindings
        // remain unused process lookups rather than a second graph registry.
        for (final task in _faceTasks) {
          output.assets.code.add(
            CodeAsset(
              package: input.packageName,
              name: '$task.dylib',
              linkMode: LookupInProcess(),
            ),
          );
        }
        output.metadata['official_android_sdk'] = '1.0.0';
        return;
      }
      await _bundleAndroid(input, output, target: target, tasks: tasks);
      return;
    }

    final isIos = target == 'ios/arm64' || target == 'ios-simulator/arm64';
    if (isIos) {
      // Google's SDK is the default on iOS devices and the arm64 simulator,
      // through the adapter core builds for every family.
      // `official_ios_sdk: false` selects the source-built face runtime.
      final adapter = core['ios_sdk_adapter'];
      if (officialIosSdk ?? true) {
        final missing = tasks.difference(officialIosTasks);
        if (missing.isNotEmpty) {
          throw UnsupportedError(
            "Google's iOS SDK serves ${officialIosTasks.join(', ')}; "
            'requested ${missing.join(', ')}.',
          );
        }
        if (adapter is! String) {
          throw StateError(tasksRuntimeRequired('mediapipe_vision', target));
        }
        // Every task binds core's adapter; the face assets alias it too.
        for (final task in _faceTasks) {
          output.assets.code.add(
            CodeAsset(
              package: input.packageName,
              name: '$task.dylib',
              linkMode: DynamicLoadingSystem(Uri(path: adapter)),
            ),
          );
        }
        output.metadata['official_ios_sdk'] = '1.0.1';
        return;
      }
      if (adapter != null) {
        // A source-built runtime next to Google's SDK registers the same
        // graphs twice once both load.
        throw StateError(
          'official_ios_sdk: false selects a source-built runtime, which '
          "cannot share a process with the official iOS SDK "
          'mediapipe_core builds. Also set hooks.user_defines.'
          'mediapipe_core.tasks_runtime: false (text and audio are '
          'then unavailable on iOS).',
        );
      }
    }

    final wheel = visionWheelReleases[target];
    if (wheel != null) {
      // Linux x64 and Windows x64: every task runs in Google's wheel library,
      // which core bundles for every family.
      final missing = tasks.difference(wheel.tasks);
      if (missing.isNotEmpty) {
        throw UnsupportedError(
          'No validated $target runtime covers ${missing.join(', ')}. '
          'Available tasks: ${wheel.tasks.join(', ')}.',
        );
      }
      final shared = core['tasks_runtime_library'];
      if (!coreRuntime || shared is! Map) {
        throw StateError(tasksRuntimeRequired('mediapipe_vision', target));
      }
      if (shared['name'] != wheel.libraryName ||
          shared['sha256'] != wheel.librarySha256) {
        throw StateError(
          'mediapipe_core bundles $shared, not the '
          '${wheel.libraryName} ${wheel.librarySha256} that '
          'mediapipe_vision validated for $target.',
        );
      }
      // The face assets alias core's copy by its file name;
      // loadOfficialDesktopRuntime() loads that copy first.
      for (final task in _faceTasks) {
        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: '$task.dylib',
            linkMode: DynamicLoadingSystem(Uri.file(wheel.libraryName)),
          ),
        );
      }
      return;
    }

    if (target == 'macos/arm64') {
      // Every task except the face pair runs in Google's engine, which core
      // bundles when the app opts in. Face Landmarker calls through it then
      // too (lib/src/io/face_landmarker_api.dart); otherwise it, and Face
      // Detector always, use the small source-built face libraries.
      final onEngine = tasks.difference({
        'face_detector',
        if (!coreRuntime) 'face_landmarker',
      });
      final unvalidated = onEngine.difference(macosEngineTasks);
      if (unvalidated.isNotEmpty) {
        throw UnsupportedError(
          "Google's macOS engine is not validated for "
          '${unvalidated.join(', ')}. Validated: '
          '${macosEngineTasks.join(', ')}.',
        );
      }
      // Without the opt-in they are left out, and creating one names the fix
      // (tasksRuntimeMissing explains why this is not a build error).
      tasks = tasks.difference(onEngine);
      if (tasks.isEmpty) return;
    }

    final published = visionRuntimeReleases.where(
      (release) => release.target == target,
    );
    if (published.isEmpty) {
      throw UnsupportedError(
        'mediapipe_vision has no runtime for $target. Supported '
        'targets: android/arm64, android/x64, ios/arm64, ios-simulator/arm64, '
        'macos/arm64, ${visionWheelReleases.keys.join(', ')} and browsers.',
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

/// A boolean user define, or null when the app leaves it unset.
bool? _optionalBool(BuildInput input, String key) {
  final value = input.userDefines[key];
  if (value != null && value is! bool) {
    throw FormatException('mediapipe_vision.$key must be a boolean.');
  }
  return value as bool?;
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
  if (hasLocalBuild && input.userDefines['prebuilt'] != true) {
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
      // Core's offline or mirror setting, forwarded as its hook metadata.
      source: hookAssetSource(input),
    );
  }
  await _bundleAliases(input, output, library: library, tasks: tasks);
}

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

/// Bundles a face runtime under each selected face task's asset. Asset IDs
/// are compile-time constants in the generated bindings, one per face task,
/// and Dart rejects duplicate physical filenames across asset IDs, so a
/// runtime serving both is copied once per name. The source builds hide
/// their symbols, so the copies coexist in one process.
Future<void> _bundleAliases(
  BuildInput input,
  BuildOutputBuilder output, {
  required File library,
  required Set<String> tasks,
  String suffix = 'dylib',
}) async {
  final digest = (await sha256.bind(library.openRead()).first).toString();
  for (final task in tasks) {
    final assetName = '$task.dylib';
    final stem = task;
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
