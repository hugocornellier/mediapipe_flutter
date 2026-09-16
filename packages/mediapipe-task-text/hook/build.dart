import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> args) => build(args, (input, output) async {
  if (input.userDefines['legacy_runtime'] == true) {
    throw UnsupportedError(
      'The 2024 text runtime has been retired. Enable '
      'mediapipe_flutter_core.tasks_runtime: true and remove legacy_runtime.',
    );
  }
  if (input.metadata['mediapipe_flutter_core']['tasks_runtime'] != true) return;
  // Only copies ephemeral generative callbacks; does not link/modify MediaPipe.
  // The bridge is plain C and is compiled for whichever target core has a
  // runtime for; core's hook has already rejected unsupported targets.
  final windows =
      input.config.buildCodeAssets && input.config.code.targetOS == OS.windows;
  await CBuilder.library(
    name: 'mediapipe_text_stream',
    assetName: 'text_stream_bridge.dylib',
    sources: ['native/text_stream_bridge.c'],
    includes: ['native'],
    flags: windows ? ['/W4', '/WX'] : ['-Wall', '-Wextra', '-Werror'],
  ).run(input: input, output: output);
});
