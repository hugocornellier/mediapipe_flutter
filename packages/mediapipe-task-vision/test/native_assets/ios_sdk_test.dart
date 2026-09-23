import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/ios_sdk.dart';
import 'package:test/test.dart';

import '../../hook/build.dart' as hook;

void main() {
  PackageUserDefines defines(Map<String, Object?> values) => PackageUserDefines(
    workspacePubspec: PackageUserDefinesSource(
      defines: values,
      basePath: Uri.directory('.'),
    ),
  );

  test('official SDK rejects unsupported targets before downloading', () async {
    // Google's iOS SDK serves every vision task, so only targets are refused.
    for (final (os, architecture, tasks) in [
      (OS.macOS, Architecture.arm64, ['face_landmarker']),
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

  test('every binding ID loads one physical iOS framework', () async {
    await testCodeBuildHook(
      mainMethod: (arguments) async {
        await build(arguments, (input, output) async {
          final library = File.fromUri(
            input.outputDirectory.resolve('mediapipe_ios.dylib'),
          );
          await library.writeAsBytes([]);
          addOfficialIosSdkAssets(
            input,
            output,
            library: library,
            tasks: {'face_landmarker', 'face_detector', 'hand_landmarker'},
          );
        });
      },
      targetOS: OS.iOS,
      targetArchitecture: Architecture.arm64,
      check: (_, output) {
        final assets = output.assets.code;
        // The shared bindings and capability probes resolve vision.dylib.
        expect(assets.map((asset) => asset.id.split('/').last).toSet(), {
          'face_landmarker.dylib',
          'face_detector.dylib',
          'hand_landmarker.dylib',
          'vision.dylib',
        });
        expect(
          assets.where((asset) => asset.linkMode is DynamicLoadingBundled),
          hasLength(1),
        );
        final aliases = assets.where(
          (asset) => asset.linkMode is DynamicLoadingSystem,
        );
        expect(aliases, hasLength(3));
        for (final alias in aliases) {
          expect(alias.file, isNull);
          expect(
            (alias.linkMode as DynamicLoadingSystem).uri.path,
            '@rpath/mediapipe_ios.framework/mediapipe_ios',
          );
        }
      },
    );
  });

  test('SDK extraction selects one slice and refuses traversal', () async {
    final temporary = await Directory.systemTemp.createTemp('ios-sdk-test-');
    addTearDown(() => temporary.delete(recursive: true));
    final zip = File('${temporary.path}/sdk.zip');
    final archive = Archive()
      ..add(
        ArchiveFile(
          'SDK.xcframework/ios-arm64/library.a',
          1,
          Uint8List.fromList([1]),
        ),
      )
      ..add(
        ArchiveFile(
          'SDK.xcframework/ios-arm64_x86_64-simulator/library.a',
          1,
          Uint8List.fromList([2]),
        ),
      );
    await zip.writeAsBytes(ZipEncoder().encode(archive));
    final destination = Directory('${temporary.path}/extracted');
    await extractOfficialIosSdkSlice(zip, destination, slice: 'ios-arm64');
    expect(
      await File(
        '${destination.path}/SDK.xcframework/ios-arm64/library.a',
      ).readAsBytes(),
      [1],
    );
    expect(
      await Directory(
        '${destination.path}/SDK.xcframework/ios-arm64_x86_64-simulator',
      ).exists(),
      isFalse,
    );
    archive.add(ArchiveFile('../escape', 1, Uint8List.fromList([3])));
    await zip.writeAsBytes(ZipEncoder().encode(archive));
    await expectLater(
      extractOfficialIosSdkSlice(zip, destination, slice: 'ios-arm64'),
      throwsA(isA<FormatException>()),
    );
    expect(await File('${temporary.path}/escape').exists(), isFalse);
  });
}
