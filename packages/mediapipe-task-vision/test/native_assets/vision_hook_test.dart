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
      (OS.linux, Architecture.arm64),
      (OS.windows, Architecture.arm64),
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

  test(
    'desktop rows reject tasks outside tested coverage before downloading',
    () {
      for (final os in [OS.linux, OS.windows]) {
        expect(
          testCodeBuildHook(
            mainMethod: hook.main,
            targetOS: os,
            targetArchitecture: Architecture.x64,
            userDefines: defines({
              'tasks': ['pose_landmarker'],
            }),
            check: (_, _) => fail('Unvalidated task unexpectedly bundled'),
          ),
          failsWith<UnsupportedError>(
            allOf(contains('$os/x64'), contains('pose_landmarker')),
          ),
        );
      }
    },
  );

  test('an unpublished release is served only from a local build', () {
    final unpublished = visionRuntimeReleases.where(
      (release) => release.archive == null,
    );
    expect(unpublished, isNotEmpty, reason: 'No unpublished row to exercise');
    for (final release in unpublished) {
      // `prebuilt: true` forces the download path, which an unpublished row
      // cannot satisfy. This keeps the test independent of whether the
      // maintainer running it happens to have a local source build.
      expect(
        testCodeBuildHook(
          mainMethod: hook.main,
          targetOS: OS.macOS,
          targetArchitecture: Architecture.arm64,
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
