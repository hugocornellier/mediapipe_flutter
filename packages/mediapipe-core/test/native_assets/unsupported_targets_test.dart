import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:test/test.dart';

void main() {
  const downloads = <String, Map<String, DownloadAsset>>{
    'android': {'arm64': (url: 'https://example.invalid/lib.so', sha256: '')},
    'ios': {'arm64': (url: 'https://example.invalid/lib.dylib', sha256: '')},
  };

  Future<void> hook(List<String> args) => build(args, (input, output) async {
    await buildNativeLibrary(
      input,
      output,
      assetName: 'bindings.dart',
      downloads: downloads,
    );
  });

  test('does not substitute arm64 for a 32-bit Android target', () async {
    await expectLater(
      testCodeBuildHook(
        mainMethod: hook,
        targetOS: OS.android,
        targetArchitecture: Architecture.arm,
        check: (_, output) => fail('Unsupported build unexpectedly succeeded'),
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('android/arm'),
        ),
      ),
    );
  });

  test('does not use an iOS device library for an arm64 simulator', () async {
    await expectLater(
      testCodeBuildHook(
        mainMethod: hook,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneSimulator,
        check: (_, output) => fail('Simulator build unexpectedly succeeded'),
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('iOS simulator'),
        ),
      ),
    );
  });
}
