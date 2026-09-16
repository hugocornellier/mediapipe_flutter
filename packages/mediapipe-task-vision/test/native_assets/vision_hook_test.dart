import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
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
    final assets = visionRuntimeReleases.map((release) => release.assetName);
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
    for (final (os, architecture) in [
      (OS.linux, Architecture.x64),
      (OS.windows, Architecture.x64),
      (OS.android, Architecture.arm64),
      (OS.iOS, Architecture.arm64),
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

  test('a task without a release on the target is refused by name', () {
    expect(
      testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
        userDefines: defines({
          'tasks': ['face_detector', 'hand_landmarker'],
        }),
        check: (_, _) => fail('Unpublished task unexpectedly bundled'),
      ),
      failsWith<UnsupportedError>(
        allOf(contains('hand_landmarker'), contains('face_detector')),
      ),
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
