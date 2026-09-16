import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_core/src/native_assets/tasks_runtime.dart';
import 'package:test/test.dart';

import '../../hook/build.dart' as hook;

void main() {
  test('build targets separate the iOS simulator from devices', () async {
    final seen = <String>[];
    Future<void> record(List<String> args) =>
        build(args, (input, output) async {
          seen.add(buildTarget(input.config.code));
        });
    for (final (os, architecture, sdk) in [
      (OS.macOS, Architecture.arm64, IOSSdk.iPhoneOS),
      (OS.iOS, Architecture.arm64, IOSSdk.iPhoneOS),
      (OS.iOS, Architecture.arm64, IOSSdk.iPhoneSimulator),
      (OS.linux, Architecture.x64, IOSSdk.iPhoneOS),
      (OS.windows, Architecture.arm64, IOSSdk.iPhoneOS),
      (OS.android, Architecture.arm, IOSSdk.iPhoneOS),
    ]) {
      await testCodeBuildHook(
        mainMethod: record,
        targetOS: os,
        targetArchitecture: architecture,
        targetIOSSdk: sdk,
        check: (_, _) {},
      );
    }
    expect(seen, [
      'macos/arm64',
      'ios/arm64',
      'ios-simulator/arm64',
      'linux/x64',
      'windows/arm64',
      'android/arm',
    ]);
  });

  test('every release row is keyed by its own target', () {
    for (final entry in tasksRuntimeReleases.entries) {
      expect(entry.value.target, entry.key);
      expect(entry.value.files.keys, containsAll(['LICENSE', 'NOTICE']));
      expect(entry.value.files[entry.value.libraryName], isNotNull);
      expect(
        RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.value.archive.sha256),
        isTrue,
      );
    }
    expect(tasksRuntimeReleases.keys, contains('macos/arm64'));
    expect(
      () => requireTasksRuntimeRelease('linux/x64'),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          allOf(contains('linux/x64'), contains('macos/arm64')),
        ),
      ),
    );
  });

  test('the hook rejects targets without a release before downloading', () {
    final defines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: {'tasks_runtime': true},
        basePath: Uri.directory('.'),
      ),
    );
    for (final (os, architecture) in [
      (OS.linux, Architecture.x64),
      (OS.windows, Architecture.x64),
      (OS.macOS, Architecture.x64),
      (OS.android, Architecture.arm64),
    ]) {
      expect(
        testCodeBuildHook(
          mainMethod: hook.main,
          targetOS: os,
          targetArchitecture: architecture,
          userDefines: defines,
          check: (_, _) => fail('Unsupported build unexpectedly succeeded'),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('$os/$architecture'),
          ),
        ),
      );
    }
  });

  test('the hook stays inert without the opt-in on any target', () async {
    await testCodeBuildHook(
      mainMethod: hook.main,
      targetOS: OS.linux,
      targetArchitecture: Architecture.x64,
      check: (_, output) => expect(output.assets.code, isEmpty),
    );
  });
}
