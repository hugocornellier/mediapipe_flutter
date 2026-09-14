import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

import '../sdk_downloads.dart';

Future<void> main(List<String> args) => build(args, (input, output) async {
  final modern =
      input.metadata['mediapipe_flutter_core']['tasks_runtime'] == true;
  final legacy = input.userDefines['legacy_runtime'] ?? !modern;
  if (legacy is! bool) {
    throw const FormatException(
      'mediapipe_flutter_text.legacy_runtime must be a boolean.',
    );
  }
  if (!legacy) {
    if (modern) {
      // Only copies ephemeral callbacks; does not link or modify MediaPipe.
      await CBuilder.library(
        name: 'mediapipe_text_stream',
        assetName: 'text_stream_bridge.dylib',
        sources: ['native/text_stream_bridge.c'],
        includes: ['native'],
        flags: ['-Wall', '-Wextra', '-Werror'],
      ).run(input: input, output: output);
    }
    return;
  }
  if (modern) {
    throw StateError(
      'The 2024 text runtime cannot coexist with MediaPipe 1.0.1. '
      'Remove legacy_runtime: true when enabling core.tasks_runtime.',
    );
  }
  await buildNativeLibrary(
    input,
    output,
    assetName:
        'src/io/third_party/mediapipe/generated/mediapipe_flutter_text_bindings.dart',
    downloads: sdkDownloads,
  );
});
