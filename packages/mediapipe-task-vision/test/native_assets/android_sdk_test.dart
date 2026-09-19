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
    await testCodeBuildHook(
      mainMethod: hook.main,
      targetOS: OS.android,
      targetArchitecture: Architecture.arm64,
      userDefines: _defines({
        'official_android_sdk': true,
        'tasks': ['face_landmarker'],
      }),
      check: (_, output) {
        final asset = output.assets.code.single;
        expect(
          asset.id,
          'package:mediapipe_flutter_vision/face_landmarker.dylib',
        );
        expect(asset.file, isNull);
        expect(asset.linkMode, isA<LookupInProcess>());
      },
    );
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
            'tasks': ['face_detector', 'face_landmarker'],
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
