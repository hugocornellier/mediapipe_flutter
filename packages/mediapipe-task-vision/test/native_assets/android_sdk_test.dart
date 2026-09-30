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
          // The face pair's C bindings stay unused process lookups; every
          // other task binds core's asset, which core leaves off on Android.
          expect(output.assets.code.map((asset) => asset.id).toSet(), {
            'package:mediapipe_flutter_vision/face_detector.dylib',
            'package:mediapipe_flutter_vision/face_landmarker.dylib',
          });
          for (final asset in output.assets.code) {
            expect(asset.file, isNull);
            expect(asset.linkMode, isA<LookupInProcess>());
          }
        },
      );
    }
  });
  test('Android SDK refuses the task it does not serve', () async {
    await expectLater(
      testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.android,
        targetArchitecture: Architecture.arm64,
        userDefines: _defines({
          'official_android_sdk': true,
          'tasks': ['interactive_segmenter_legacy', 'face_landmarker'],
        }),
        check: (_, _) => fail('Invalid selection succeeded'),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });
  test('settings for other platforms are ignored on Android', () async {
    // An app's user_defines cover all of its targets.
    await testCodeBuildHook(
      mainMethod: hook.main,
      targetOS: OS.android,
      targetArchitecture: Architecture.arm64,
      userDefines: _defines({
        'tasks': ['face_landmarker', 'hand_landmarker'],
        'official_ios_sdk': false,
      }),
      check: (_, output) {
        for (final asset in output.assets.code) {
          expect(asset.linkMode, isA<LookupInProcess>());
        }
      },
    );
  });
  test('Android uses the SDK unless the source runtime is chosen', () async {
    await testCodeBuildHook(
      mainMethod: hook.main,
      targetOS: OS.android,
      targetArchitecture: Architecture.x64,
      userDefines: _defines({
        'tasks': ['pose_landmarker', 'face_landmarker'],
      }),
      check: (_, output) {
        expect(output.assets.code, isNotEmpty);
        for (final asset in output.assets.code) {
          expect(asset.file, isNull);
          expect(asset.linkMode, isA<LookupInProcess>());
        }
      },
    );
    // Opting out takes the source-built face runtime: bundled files when a
    // maintainer build exists here, otherwise a message on how to build it.
    try {
      await testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.android,
        targetArchitecture: Architecture.x64,
        userDefines: _defines({
          'official_android_sdk': false,
          'tasks': ['face_landmarker'],
        }),
        check: (_, output) {
          expect(
            output.assets.code.every((asset) => asset.file != null),
            isTrue,
          );
        },
      );
    } on StateError catch (error) {
      expect('$error', contains('local source build'));
    }
  });
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
