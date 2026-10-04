import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_core/src/native_assets/tasks_runtime.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// The Audio Classifier runs on Google's MediaPipe engine, which
/// mediapipe_core bundles; browsers and Android run Google's own SDKs
/// through this package's plugin instead. An app that turned the engine off
/// where it is on by default fails the build with the fix; on macOS, where it
/// is opt-in, creating the task names the fix instead ([tasksRuntimeMissing]).
Future<void> main(List<String> args) => build(args, (input, output) async {
  if (!input.config.buildCodeAssets) return;
  final target = buildTarget(input.config.code);
  final enabled = input.metadata['mediapipe_core']['tasks_runtime'] == true;
  if (tasksRuntimeMissing(target, enabled: enabled)) {
    throw StateError(tasksRuntimeRequired('mediapipe_audio', target));
  }
  if (!enabled) return;
  // The stream bridge only copies Google's audio stream results inside its
  // callback; it does not link or modify MediaPipe. It is plain C, compiled
  // for whichever target core has a runtime for.
  final windows = input.config.code.targetOS == OS.windows;
  await CBuilder.library(
    name: 'mediapipe_audio_stream',
    assetName: 'audio_stream_bridge.dylib',
    sources: ['native/audio_stream_bridge.c'],
    includes: ['native'],
    flags: windows ? ['/W4', '/WX'] : ['-Wall', '-Wextra', '-Werror'],
  ).run(input: input, output: output);
});
