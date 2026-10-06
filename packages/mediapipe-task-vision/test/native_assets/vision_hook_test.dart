import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_core/src/native_assets/tasks_runtime.dart';
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

  test('release rows are the source-built face runtimes', () {
    // Google's engine is core's; this package only builds the face pair.
    final assets = visionRuntimeReleases.map(
      (release) => (release.target, release.assetName),
    );
    expect(assets.toSet().length, assets.length);
    for (final release in visionRuntimeReleases) {
      expect(release.tasks, isNotEmpty);
      expect(
        release.tasks.difference({'face_detector', 'face_landmarker'}),
        isEmpty,
      );
      expect(release.localBuildDirectory, endsWith('/'));
    }
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
    // export it.
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
    };
    expect(visionWheelReleases['linux/x64']!.tasks, {
      ...validated,
      'interactive_segmenter',
    });
    expect(visionWheelReleases['windows/x64']!.tasks, validated);
    expect(visionTasks.difference(validated), {'interactive_segmenter'});
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

  test('desktop face assets alias the copy core bundles', () async {
    // What core's hook publishes when it bundles a desktop wheel.
    Map<String, List<EncodedAsset>> core(Object value) => {
      'mediapipe_core': [
        EncodedAsset('hooks/metadata', {'key': 'tasks_runtime', 'value': true}),
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
          // Pose binds core's asset directly; only the face pair has its own
          // asset IDs, and both name core's file.
          expect(output.assets.code.map((asset) => asset.id).toSet(), {
            'package:mediapipe_vision/face_detector.dylib',
            'package:mediapipe_vision/face_landmarker.dylib',
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
      // The engine is on by default here; turning it off leaves no runtime.
      await expectLater(
        testCodeBuildHook(
          mainMethod: hook.main,
          targetOS: os,
          targetArchitecture: Architecture.x64,
          check: (_, _) => fail('Vision built without an engine'),
        ),
        failsWith<StateError>(contains('Remove tasks_runtime: false')),
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

  test(
    "every task but Face Detector is validated on Google's macOS engine",
    () {
      expect(macosEngineTasks, visionTasks.difference({'face_detector'}));
    },
  );

  test("without core's opt-in, macOS leaves the engine tasks out", () async {
    // Not a build error: `dart run` builds an iOS or Android app's hooks for
    // a Mac host too. Creating such a task names the opt-in instead.
    await testCodeBuildHook(
      mainMethod: hook.main,
      targetOS: OS.macOS,
      targetArchitecture: Architecture.arm64,
      userDefines: defines({
        'tasks': [
          'hand_landmarker',
          'object_detector',
          'interactive_segmenter',
        ],
      }),
      check: (_, output) => expect(output.assets.code, isEmpty),
    );
  });

  test("with core's engine, macOS vision adds no second copy", () async {
    // Hand, the segmenter and Face Landmarker all call core's one asset, and
    // settings for other platforms are ignored here.
    await testCodeBuildHook(
      mainMethod: hook.main,
      targetOS: OS.macOS,
      targetArchitecture: Architecture.arm64,
      userDefines: defines({
        'tasks': [
          'face_landmarker',
          'hand_landmarker',
          'interactive_segmenter',
        ],
        'official_ios_sdk': true,
        'official_android_sdk': false,
      }),
      assets: {
        'mediapipe_core': [
          EncodedAsset('hooks/metadata', {
            'key': 'tasks_runtime',
            'value': true,
          }),
        ],
      },
      check: (_, output) => expect(output.assets.code, isEmpty),
    );
  });

  test('simulator rejects tasks whose exports lack validated inference', () {
    expect(
      testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneSimulator,
        userDefines: defines({
          'official_ios_sdk': false,
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
}
