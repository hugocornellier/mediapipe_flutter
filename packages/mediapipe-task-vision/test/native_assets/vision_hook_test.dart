import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/src/native_assets/tasks_runtime.dart';
import 'package:test/test.dart';

import '../../hook/build.dart' as hook;
import '../../sdk_downloads.dart';

void main() {
  PackageUserDefines defines(Map<String, Object?> values) => PackageUserDefines(
    workspacePubspec: PackageUserDefinesSource(
      defines: values,
      basePath: Uri.directory('.'),
    ),
  );

  Matcher failsWith<T extends Error>(Matcher message) => throwsA(
    isA<T>().having(
      (error) => (error as dynamic).message.toString(),
      'message',
      message,
    ),
  );

  test('release rows cover published targets with distinct assets', () {
    final assets = visionRuntimeReleases.map(
      (release) => (release.target, release.assetName),
    );
    expect(assets.toSet().length, assets.length);
    for (final release in visionRuntimeReleases) {
      expect(release.tasks, isNotEmpty);
      expect(release.tasks.every(visionTasks.contains), isTrue);
      expect(release.tasks, isNot(contains(sharedRuntimeTask)));
      expect(release.localBuildDirectory, endsWith('/'));
    }
    expect(visionTasks, contains(sharedRuntimeTask));
  });

  test('targets without any runtime name the published ones', () {
    // Both iOS slices now have a row, so neither belongs here. A target that
    // has a row but no published archive fails later, and differently: the
    // unpublished-release test below covers that.
    for (final (os, architecture) in [
      (OS.linux, Architecture.arm64),
      (OS.windows, Architecture.arm64),
      (OS.android, Architecture.arm),
      (OS.macOS, Architecture.x64),
    ]) {
      expect(
        testCodeBuildHook(
          mainMethod: hook.main,
          targetOS: os,
          targetArchitecture: architecture,
          check: (_, _) => fail('Unsupported build unexpectedly succeeded'),
        ),
        failsWith<UnsupportedError>(
          allOf(contains('$os/$architecture'), contains('macos/arm64')),
        ),
      );
    }
  });

  test('desktop rows cover exactly what the desktop jobs validate', () {
    // The hook refuses any task missing from these rows, so widening them
    // without adding the task to tool/test_desktop.py would claim coverage
    // nothing proves. Linux's 1.0.1 wheel also serves the stateful Interactive
    // Segmenter (test_desktop.py --interactive-segmenter); Windows' does not
    // export it, and core's shared runtime serves it on macOS.
    const validated = {
      'face_detector',
      'face_landmarker',
      'object_detector',
      'image_classifier',
      'image_embedder',
      'hand_landmarker',
      'gesture_recognizer',
      'pose_landmarker',
      'holistic_landmarker',
      'image_segmenter',
      'interactive_segmenter_legacy',
    };
    expect(visionWheelReleases['linux/x64']!.tasks, {
      ...validated,
      sharedRuntimeTask,
    });
    expect(visionWheelReleases['windows/x64']!.tasks, validated);
    expect(visionTasks.difference(validated), {sharedRuntimeTask});
  });

  test('desktop rows pin the library core bundles for text and audio', () {
    // An app with vision and text or audio loads one copy: core bundles it
    // and the vision hook maps its assets onto it, which needs the same file.
    expect(visionWheelReleases.keys, unorderedEquals(tasksWheelRuntimes.keys));
    for (final MapEntry(key: target, value: vision)
        in visionWheelReleases.entries) {
      final core = tasksWheelRuntimes[target]!;
      expect(vision.target, core.target);
      expect(vision.version, core.version);
      expect(vision.wheel, core.wheel);
      expect(vision.libraryName, core.libraryName);
      expect(vision.librarySha256, core.librarySha256);
      expect(vision.notices, core.notices);
    }
  });

  test('desktop tasks resolve to the copy core bundles', () async {
    // What core's hook publishes when tasks_runtime bundles a desktop wheel.
    Map<String, List<EncodedAsset>> core(Object value) => {
      'mediapipe_flutter_core': [
        EncodedAsset('hooks/metadata', {
          'key': 'tasks_runtime_library',
          'value': value,
        }),
      ],
    };
    for (final (os, target) in [
      (OS.linux, 'linux/x64'),
      (OS.windows, 'windows/x64'),
    ]) {
      final release = visionWheelReleases[target]!;
      await testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: os,
        targetArchitecture: Architecture.x64,
        userDefines: defines({
          'tasks': ['face_landmarker', 'pose_landmarker'],
        }),
        assets: core({
          'name': release.libraryName,
          'sha256': release.librarySha256,
        }),
        check: (_, output) {
          expect(output.assets.code.map((asset) => asset.id).toSet(), {
            'package:mediapipe_flutter_vision/vision.dylib',
            'package:mediapipe_flutter_vision/face_landmarker.dylib',
          });
          for (final asset in output.assets.code) {
            expect(asset.file, isNull);
            expect(
              asset.linkMode,
              isA<DynamicLoadingSystem>().having(
                (mode) => mode.uri,
                'uri',
                Uri.file(release.libraryName),
              ),
            );
          }
        },
      );
      await expectLater(
        testCodeBuildHook(
          mainMethod: hook.main,
          targetOS: os,
          targetArchitecture: Architecture.x64,
          userDefines: defines({
            'tasks': ['face_landmarker'],
          }),
          assets: core({'name': release.libraryName, 'sha256': '0' * 64}),
          check: (_, _) => fail('A second, different library was accepted'),
        ),
        failsWith<StateError>(contains(release.librarySha256)),
      );
    }
  });

  test('an unpublished release is served only from a local build', () {
    final unpublished = visionRuntimeReleases.where(
      (release) => release.archive == null,
    );
    expect(unpublished, isNotEmpty, reason: 'No unpublished row to exercise');
    for (final release in unpublished) {
      // Build each row on its own target. The two iOS slices are separate
      // artifacts built with different SDKs, so asking for the wrong one here
      // silently exercises a different row than the one under test.
      final simulator = release.target.startsWith('ios-simulator');
      final device = release.target == 'ios/arm64';
      // `prebuilt: true` forces the download path, which an unpublished row
      // cannot satisfy. This keeps the test independent of whether the
      // maintainer running it happens to have a local source build.
      expect(
        testCodeBuildHook(
          mainMethod: hook.main,
          targetOS: simulator || device ? OS.iOS : OS.macOS,
          targetArchitecture: Architecture.arm64,
          targetIOSSdk: device ? IOSSdk.iPhoneOS : IOSSdk.iPhoneSimulator,
          userDefines: defines({
            'tasks': [release.tasks.first],
            'prebuilt': true,
          }),
          check: (_, _) => fail('Unpublished release unexpectedly downloaded'),
        ),
        failsWith<StateError>(
          allOf(
            contains(release.release),
            contains('not published yet'),
            contains(release.tasks.first),
          ),
        ),
      );
    }
  });

  test('published rows pin an archive digest', () {
    for (final release in visionRuntimeReleases) {
      if (release.archive case final archive?) {
        expect(archive.sha256, matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(archive.url, startsWith('https://'));
      }
      expect(release.librarySha256, matches(RegExp(r'^[a-f0-9]{64}$')));
    }
  });

  test('official gallery landmark runtime pins wheel and prepared bytes', () {
    final release = officialMacosLandmarkRuntime;
    expect(release.target, 'macos/arm64');
    expect(release.tasks, {
      'face_landmarker',
      'gesture_recognizer',
      'hand_landmarker',
      'holistic_landmarker',
      'image_classifier',
      'image_embedder',
      'image_segmenter',
      'interactive_segmenter_legacy',
      'object_detector',
      'pose_landmarker',
    });
    expect(release.archive, isNull);
    expect(release.libraryName, 'libmediapipe.dylib');
    expect(release.librarySha256, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(release.officialWheel, isNotNull);
    expect(
      release.officialWheel!.wheel.sha256,
      matches(RegExp(r'^[a-f0-9]{64}$')),
    );
    expect(
      release.officialWheel!.librarySha256,
      matches(RegExp(r'^[a-f0-9]{64}$')),
    );
    expect(release.officialWheel!.delegates, {'cpu', 'gpu'});
  });

  test('official gallery landmark runtime requires its task and target', () {
    expect(
      testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
        userDefines: defines({
          'tasks': ['face_detector'],
          'official_macos_landmark_tasks': true,
        }),
        check: (_, _) => fail('Official runtime accepted without its task'),
      ),
      failsWith<StateError>(contains('requires at least one')),
    );
    expect(
      testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.linux,
        targetArchitecture: Architecture.x64,
        userDefines: defines({
          'tasks': ['face_landmarker'],
          'official_macos_landmark_tasks': true,
        }),
        check: (_, _) => fail('Official macOS runtime accepted on Linux'),
      ),
      failsWith<UnsupportedError>(contains('macos/arm64')),
    );
  });

  test(
    'official macOS runtime is bundled once when face shares it',
    () async {
      // Google's monolith shares its graph registry between loaded images, so
      // a second copy for the face asset would abort on registration.
      await testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
        userDefines: defines({
          'tasks': ['face_landmarker', 'hand_landmarker'],
          'official_macos_landmark_tasks': true,
        }),
        check: (_, output) {
          final assets = output.assets.code.toList();
          expect(assets.map((asset) => asset.id), [
            'package:mediapipe_flutter_vision/vision.dylib',
          ]);
          expect(assets.single.linkMode, isA<DynamicLoadingBundled>());
        },
      );
    },
    skip:
        File(
          '${officialMacosLandmarkRuntime.localBuildDirectory}'
          '${officialMacosLandmarkRuntime.libraryName}',
        ).existsSync()
        ? false
        : 'Run tool/prepare_official_macos_landmark_runtime.py first.',
  );

  test('simulator rejects tasks whose exports lack validated inference', () {
    expect(
      testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneSimulator,
        userDefines: defines({
          'tasks': ['object_detector'],
        }),
        check: (_, _) =>
            fail('Unvalidated simulator task unexpectedly accepted'),
      ),
      failsWith<UnsupportedError>(contains('object_detector')),
    );
  });

  test('Android requires a source build instead of inventing a download', () {
    for (final architecture in [Architecture.arm64, Architecture.x64]) {
      expect(
        testCodeBuildHook(
          mainMethod: hook.main,
          targetOS: OS.android,
          targetArchitecture: architecture,
          userDefines: defines({
            'official_android_sdk': false,
            'prebuilt': true,
          }),
          check: (_, _) => fail('Android unexpectedly downloaded a runtime'),
        ),
        failsWith<StateError>(contains('No Android public archive is pinned')),
      );
    }
  });

  test('Android face CI rejects other exported task APIs', () {
    expect(
      testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.android,
        targetArchitecture: Architecture.x64,
        userDefines: defines({
          'official_android_sdk': false,
          'tasks': ['object_detector'],
        }),
        check: (_, _) => fail('Unvalidated Android task unexpectedly accepted'),
      ),
      failsWith<UnsupportedError>(contains('object_detector')),
    );
  });

  test('unknown task names list every accepted task', () {
    expect(
      testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
        userDefines: defines({
          'tasks': ['face_detecter'],
        }),
        check: (_, _) => fail('Invalid selection unexpectedly accepted'),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('pose_landmarker'), contains('interactive_segmenter')),
        ),
      ),
    );
  });

  test('MagicTouch requires the shared runtime opt-in', () {
    expect(
      testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
        userDefines: defines({
          'tasks': ['interactive_segmenter'],
        }),
        check: (_, _) => fail('Segmenter bundled without the core runtime'),
      ),
      failsWith<StateError>(contains('tasks_runtime: true')),
    );
  });
}
