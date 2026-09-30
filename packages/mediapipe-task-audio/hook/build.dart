import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_core/src/native_assets/tasks_runtime.dart';

/// The Audio Classifier runs on Google's MediaPipe engine, which
/// mediapipe_flutter_core bundles; browsers and Android run Google's own SDKs
/// through this package's plugin instead. An app that turned the engine off
/// where it is on by default fails the build with the fix; on macOS, where it
/// is opt-in, creating the task names the fix instead ([tasksRuntimeMissing]).
Future<void> main(List<String> args) => build(args, (input, output) async {
  if (!input.config.buildCodeAssets) return;
  final target = buildTarget(input.config.code);
  final enabled =
      input.metadata['mediapipe_flutter_core']['tasks_runtime'] == true;
  if (tasksRuntimeMissing(target, enabled: enabled)) {
    throw StateError(tasksRuntimeRequired('mediapipe_flutter_audio', target));
  }
});
