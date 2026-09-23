import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';
import '../../hook/build.dart' as hook;

PackageUserDefines _defines(Map<String, Object?> values) => PackageUserDefines(
  workspacePubspec: PackageUserDefinesSource(
    defines: values,
    basePath: Uri.directory('.'),
  ),
);

void main() {
  test('Android SDK leaves JNI ownership with the Flutter plugin', () async {
    for (final tasks in [
      ['face_landmarker'],
      ['hand_landmarker'],
      ['face_landmarker', 'hand_landmarker'],
    ]) {
      await testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.android,
        targetArchitecture: Architecture.arm64,
        userDefines: _defines({'official_android_sdk': true, 'tasks': tasks}),
        check: (_, output) {
          expect(output.assets.code.map((asset) => asset.id).toSet(), {
            for (final task in [...tasks, 'vision'])
              'package:mediapipe_flutter_vision/$task.dylib',
          });
          for (final asset in output.assets.code) {
            expect(asset.file, isNull);
            expect(asset.linkMode, isA<LookupInProcess>());
          }
        },
      );
    }
  });
  test(
    'Android SDK refuses wrong targets, mixed tasks and mixed SDKs',
    () async {
      for (final (os, defines) in [
        (
          OS.macOS,
          {
            'official_android_sdk': true,
            'tasks': ['face_landmarker'],
          },
        ),
        (
          OS.android,
          {
            'official_android_sdk': true,
            'tasks': ['interactive_segmenter_legacy', 'face_landmarker'],
          },
        ),
        (
          OS.android,
          {
            'official_android_sdk': true,
            'tasks': ['face_landmarker'],
            'official_ios_sdk': true,
          },
        ),
        (
          OS.android,
          {
            'official_android_sdk': true,
            'tasks': ['face_landmarker'],
            'official_macos_landmark_tasks': true,
          },
        ),
      ]) {
        await expectLater(
          testCodeBuildHook(
            mainMethod: hook.main,
            targetOS: os,
            targetArchitecture: Architecture.arm64,
            userDefines: _defines(defines),
            check: (_, _) => fail('Invalid selection succeeded'),
          ),
          throwsA(isA<UnsupportedError>()),
        );
      }
    },
  );
  test('Android SDK option must be boolean', () async {
    await expectLater(
      testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.android,
        targetArchitecture: Architecture.arm64,
        userDefines: _defines({'official_android_sdk': 'yes'}),
        check: (_, _) => fail('Invalid option succeeded'),
      ),
      throwsFormatException,
    );
  });
}
