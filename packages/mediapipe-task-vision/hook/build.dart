import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

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
    final library = File.fromUri(
      input.packageRoot.resolve('build/native/libface_detector.dylib'),
    );
    if (!await library.exists()) {
      throw StateError(
        'Build the pinned MediaPipe runtime first: '
        'python3 tool/build_native.py (from the mediapipe-task-vision directory). '
        'Prebuilt release artifacts have not been published yet.',
      );
    }
    final manifestFile = File.fromUri(
      input.packageRoot.resolve('build/native/manifest.json'),
    );
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    if (manifest['revision'] != '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120' ||
        manifest['opencv_revision'] !=
            '49486f61fb25722cbcf586b7f4320921d46fb38e' ||
        manifest['platform'] != 'macos' ||
        manifest['architecture'] != 'arm64' ||
        (await sha256.bind(library.openRead()).first).toString() !=
            manifest['sha256']) {
      throw StateError(
        'Native artifact provenance/hash mismatch; rebuild with tool/build_native.py.',
      );
    }
    output.dependencies.add(library.uri);
    output.dependencies.add(manifestFile.uri);
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
