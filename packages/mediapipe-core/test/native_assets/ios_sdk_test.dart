import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_core/src/native_assets/ios_sdk.dart';
import 'package:mediapipe_core/src/native_assets/tasks_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('the adapter is one bundled image every family resolves to', () async {
    await testCodeBuildHook(
      mainMethod: (arguments) async {
        await build(arguments, (input, output) async {
          final library = File.fromUri(
            input.outputDirectory.resolve('mediapipe_ios.dylib'),
          );
          await library.writeAsBytes([]);
          addOfficialIosSdkAsset(input, output, library: library);
        });
      },
      targetOS: OS.iOS,
      targetArchitecture: Architecture.arm64,
      check: (_, output) {
        final asset = output.assets.code.single;
        expect(asset.id, 'package:mediapipe_core/$tasksRuntimeAssetName');
        expect(asset.linkMode, isA<DynamicLoadingBundled>());
        expect(asset.file!.pathSegments.last, 'mediapipe_ios.dylib');
        expect(metadataOf(output)['ios_sdk_adapter'], tasksRuntimeIosAdapter);
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

/// The metadata a hook reported, by key.
Map<String, Object?> metadataOf(BuildOutput output) => {
  for (final asset in output.assets.encodedAssetsForBuild)
    if (asset.type == 'hooks/metadata')
      asset.encoding['key'] as String: asset.encoding['value'],
};
