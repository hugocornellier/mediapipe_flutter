import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/interactive_segmenter_library.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/vision_library.dart';

import '../sdk_downloads.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final simulator =
        code.targetOS == OS.iOS && code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
    if ((code.targetOS != OS.macOS && !simulator) ||
        code.targetArchitecture != Architecture.arm64) {
      throw UnsupportedError(
        'mediapipe_flutter_vision supports macOS arm64 and CPU inference '
        'on the arm64 iOS simulator. Physical iOS devices and other '
        'architectures are not supported yet. '
        'Requested ${code.targetOS}/${code.targetArchitecture}.',
      );
    }
    if (code.linkModePreference == LinkModePreference.static) {
      throw UnsupportedError('MediaPipe requires dynamic library bundling.');
    }
    // Flutter 3.44 reports a fixed iOS targetVersion of 13 here, independently
    // of Runner's deployment target. It cannot validate the app's minimum OS.
    // Our arm64 simulator binaries require iOS 14; see tool/IOS_SIMULATOR.md.
    final usePrebuilt = input.userDefines['prebuilt'];
    if (usePrebuilt != null && usePrebuilt is! bool) {
      throw const FormatException(
        'mediapipe_flutter_vision.prebuilt must be a boolean.',
      );
    }
    final selection =
        input.userDefines['tasks'] ?? ['face_detector', 'face_landmarker'];
    if (selection is! List ||
        selection.isEmpty ||
        selection.any(
          (task) =>
              task != 'face_detector' &&
              task != 'face_landmarker' &&
              task != 'interactive_segmenter',
        )) {
      throw const FormatException(
        'mediapipe_flutter_vision.tasks must be a nonempty list of '
        'face_detector, face_landmarker and/or interactive_segmenter.',
      );
    }
    output.dependencies.add(input.packageRoot.resolve('sdk_downloads.dart'));
    for (final task in selection.toSet()) {
      final landmarker = task == 'face_landmarker';
      final segmenter = task == 'interactive_segmenter';
      if (segmenter && simulator) {
        throw UnsupportedError(
          'Interactive Segmenter currently supports macOS arm64 only.',
        );
      }
      final local = Directory.fromUri(
        input.packageRoot.resolve(
          simulator
              ? 'build/native/ios-simulator/arm64/$task/'
              : landmarker || segmenter
              ? 'build/native/$task/'
              : 'build/native/',
        ),
      );
      final libraryName = 'lib$task.dylib';
      final File library;
      if (segmenter) {
        library =
            usePrebuilt != true &&
                await File.fromUri(local.uri.resolve(libraryName)).exists()
            ? await validateInteractiveSegmenterLibrary(local)
            : await downloadInteractiveSegmenterLibrary(
                asset: interactiveSegmenterArchive,
                cache: Directory.fromUri(
                  input.outputDirectoryShared.resolve(
                    'macos/arm64/interactive_segmenter/',
                  ),
                ),
              );
      } else if (simulator) {
        if (usePrebuilt == true ||
            !await File.fromUri(local.uri.resolve(libraryName)).exists()) {
          throw StateError(
            'iOS simulator runtimes are currently local development builds. '
            'Run python3 tool/build_ios_simulator.py in the vision package '
            'and omit prebuilt: true. No macOS library can substitute for '
            'an iOS simulator library.',
          );
        }
        library = await validateVisionLibrary(
          local,
          libraryName: libraryName,
          target: VisionLibraryTarget.iosSimulatorArm64,
        );
      } else if (usePrebuilt != true &&
          await File.fromUri(local.uri.resolve(libraryName)).exists()) {
        // Maintainers can continue testing builds made by tool/build_native.py.
        // A normal dependency installation has no package-local build directory.
        library = await validateVisionLibrary(local, libraryName: libraryName);
      } else {
        library = await downloadVisionLibrary(
          asset: landmarker ? faceLandmarkerArchive : faceDetectorArchive,
          librarySha256: landmarker
              ? faceLandmarkerLibrarySha256
              : faceDetectorLibrarySha256,
          libraryName: libraryName,
          cache: Directory.fromUri(
            input.outputDirectoryShared.resolve('macos/arm64/'),
          ),
        );
      }
      output.dependencies.add(library.uri);
      output.dependencies.add(library.parent.uri.resolve('manifest.json'));
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: '$task.dylib',
          linkMode: DynamicLoadingBundled(),
          file: library.uri,
        ),
      );
    }
  });
}
