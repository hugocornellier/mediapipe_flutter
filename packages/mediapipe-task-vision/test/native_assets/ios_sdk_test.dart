import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../../hook/build.dart' as hook;

void main() {
  PackageUserDefines defines(Map<String, Object?> values) => PackageUserDefines(
    workspacePubspec: PackageUserDefinesSource(
      defines: values,
      basePath: Uri.directory('.'),
    ),
  );
  // What mediapipe_flutter_core's hook reports once it has built the adapter.
  final coreAdapter = [
    EncodedAsset('hooks/metadata', {'key': 'tasks_runtime', 'value': true}),
    EncodedAsset('hooks/metadata', {
      'key': 'ios_sdk_adapter',
      'value': '@rpath/mediapipe_ios.framework/mediapipe_ios',
    }),
  ];

  test('official SDK rejects unsupported targets before downloading', () async {
    // Google's iOS SDK serves every vision task, so only targets are refused.
    // (On other platforms the iOS setting is ignored.)
    for (final (os, architecture, tasks) in [
      (OS.iOS, Architecture.x64, ['face_landmarker']),
      (OS.iOS, Architecture.x64, ['face_landmarker', 'interactive_segmenter']),
    ]) {
      await expectLater(
        testCodeBuildHook(
          mainMethod: hook.main,
          targetOS: os,
          targetArchitecture: architecture,
          userDefines: defines({'official_ios_sdk': true, 'tasks': tasks}),
          check: (_, _) => fail('Unsupported SDK request succeeded'),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    }
  });

  test(
    'official SDK option is typed and cannot select two platform runtimes',
    () async {
      for (final options in [
        {'official_ios_sdk': 'yes'},
        // Removed: macOS tasks now run on core's engine.
        {'official_ios_sdk': true, 'official_macos_landmark_tasks': true},
      ]) {
        await expectLater(
          testCodeBuildHook(
            mainMethod: hook.main,
            targetOS: OS.iOS,
            targetArchitecture: Architecture.arm64,
            userDefines: defines(options),
            check: (_, _) => fail('Invalid SDK selection succeeded'),
          ),
          throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
        );
      }
    },
  );

  test('every binding ID resolves to core\'s one adapter image', () async {
    await testCodeBuildHook(
      mainMethod: hook.main,
      targetOS: OS.iOS,
      targetArchitecture: Architecture.arm64,
      userDefines: defines({
        'tasks': ['face_landmarker', 'face_detector', 'hand_landmarker'],
      }),
      assets: {'mediapipe_flutter_core': coreAdapter},
      check: (_, output) {
        final assets = output.assets.code;
        // Hand binds core's asset directly; the face pair's own asset IDs
        // alias the same image.
        expect(assets.map((asset) => asset.id.split('/').last).toSet(), {
          'face_landmarker.dylib',
          'face_detector.dylib',
        });
        for (final asset in assets) {
          expect(asset.file, isNull);
          expect(
            (asset.linkMode as DynamicLoadingSystem).uri.path,
            '@rpath/mediapipe_ios.framework/mediapipe_ios',
          );
        }
      },
    );
  });

  test('the official SDK needs core\'s adapter', () async {
    await expectLater(
      testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        userDefines: defines({
          'tasks': ['face_landmarker'],
        }),
        check: (_, _) => fail('Built without core\'s adapter'),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'a source-built opt-out refuses to share a process with the SDK',
    () async {
      await expectLater(
        testCodeBuildHook(
          mainMethod: hook.main,
          targetOS: OS.iOS,
          targetArchitecture: Architecture.arm64,
          targetIOSSdk: IOSSdk.iPhoneSimulator,
          userDefines: defines({
            'official_ios_sdk': false,
            'tasks': ['face_landmarker'],
          }),
          assets: {'mediapipe_flutter_core': coreAdapter},
          check: (_, _) => fail('Two MediaPipe images were allowed'),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}
