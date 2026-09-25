import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/capabilities.dart';
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

  test('desktop rows take one unmodified library from an official wheel', () {
    for (final MapEntry(key: target, value: runtime)
        in tasksWheelRuntimes.entries) {
      expect(runtime.target, target);
      expect(tasksRuntimeReleases, isNot(contains(target)));
      expect(runtime.wheel.url, startsWith('https://files.pythonhosted.org/'));
      expect(
        runtime.wheel.url,
        endsWith(
          target == 'linux/x64'
              ? 'mediapipe-${runtime.version}-py3-none-manylinux_2_28_x86_64.whl'
              : 'mediapipe-${runtime.version}-py3-none-win_amd64.whl',
        ),
      );
      for (final digest in [
        runtime.wheel.sha256,
        runtime.librarySha256,
        ...runtime.notices.values,
      ]) {
        expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(digest), isTrue);
      }
      expect(runtime.notices.keys, unorderedEquals(['LICENSE', 'NOTICE']));
    }
    expect(
      tasksWheelRuntimes.keys,
      unorderedEquals(['linux/x64', 'windows/x64']),
    );
    // The capability table claims exactly the targets the hook can bundle.
    expect(
      tasksRuntimeTargets.keys,
      unorderedEquals([
        ...tasksRuntimeReleases.keys,
        ...tasksWheelRuntimes.keys,
        'ios/arm64',
      ]),
    );
    expect(macosTasksRuntimeTargets.keys, tasksRuntimeReleases.keys);
  });

  test('the hook rejects targets without a release before downloading', () {
    final defines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: {'tasks_runtime': true},
        basePath: Uri.directory('.'),
      ),
    );
    for (final (os, architecture) in [
      (OS.linux, Architecture.arm64),
      (OS.windows, Architecture.arm64),
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

  test("iOS resolves to the vision package's SDK adapter", () async {
    for (final sdk in [IOSSdk.iPhoneOS, IOSSdk.iPhoneSimulator]) {
      await testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: sdk,
        userDefines: PackageUserDefines(
          workspacePubspec: PackageUserDefinesSource(
            defines: {'tasks_runtime': true},
            basePath: Uri.directory('.'),
          ),
        ),
        check: (_, output) {
          final asset = output.assets.code.single;
          expect(asset.file, isNull);
          expect(
            asset.linkMode,
            isA<DynamicLoadingSystem>().having(
              (mode) => mode.uri.path,
              'path',
              tasksRuntimeIosAdapter,
            ),
          );
        },
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
