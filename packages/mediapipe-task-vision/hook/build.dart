import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/face_detector_library.dart';

import '../sdk_downloads.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    if (code.targetOS != OS.macOS ||
        code.targetArchitecture != Architecture.arm64) {
      throw UnsupportedError(
        'mediapipe_flutter_vision currently supports macOS arm64 only. '
        'Requested ${code.targetOS}/${code.targetArchitecture}.',
      );
    }
    if (code.linkModePreference == LinkModePreference.static) {
      throw UnsupportedError('MediaPipe requires dynamic library bundling.');
    }
    final local = Directory.fromUri(input.packageRoot.resolve('build/native/'));
    final usePrebuilt = input.userDefines['prebuilt'];
    if (usePrebuilt != null && usePrebuilt is! bool) {
      throw const FormatException(
        'mediapipe_flutter_vision.prebuilt must be a boolean.',
      );
    }
    final File library;
    if (usePrebuilt != true &&
        await File.fromUri(
          local.uri.resolve('libface_detector.dylib'),
        ).exists()) {
      // Maintainers can continue testing builds made by tool/build_native.py.
      // A normal dependency installation has no package-local build directory.
      library = await validateFaceDetectorLibrary(local);
    } else {
      library = await downloadFaceDetectorLibrary(
        asset: faceDetectorArchive,
        librarySha256: faceDetectorLibrarySha256,
        cache: Directory.fromUri(
          input.outputDirectoryShared.resolve('macos/arm64/'),
        ),
      );
    }
    output.dependencies.add(input.packageRoot.resolve('sdk_downloads.dart'));
    output.dependencies.add(library.uri);
    output.dependencies.add(library.parent.uri.resolve('manifest.json'));
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'face_detector.dylib',
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
  });
}
