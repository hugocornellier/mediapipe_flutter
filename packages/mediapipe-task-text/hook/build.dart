import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_core/src/native_assets/tasks_runtime.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> args) => build(args, (input, output) async {
  if (input.userDefines['legacy_runtime'] == true) {
    throw UnsupportedError(
      'The 2024 text runtime has been retired. Enable '
      'mediapipe_core.tasks_runtime: true and remove legacy_runtime.',
    );
  }
  if (!input.config.buildCodeAssets) return;
  if (input.metadata['mediapipe_core']['tasks_runtime'] != true) {
    // Browsers and Android run Google's own SDKs through this plugin instead.
    // On macOS the engine is opt-in, and creating a task names the fix.
    final target = buildTarget(input.config.code);
    if (tasksRuntimeMissing(target, enabled: false)) {
      throw StateError(tasksRuntimeRequired('mediapipe_text', target));
    }
    return;
  }
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
