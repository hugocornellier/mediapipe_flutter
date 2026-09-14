import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/src/native_assets/tasks_runtime.dart';

Future<void> main(List<String> arguments) => build(arguments, (
  input,
  output,
) async {
  final enabled = input.userDefines['tasks_runtime'] ?? false;
  if (enabled is! bool) {
    throw const FormatException(
      'mediapipe_flutter_core.tasks_runtime must be a boolean.',
    );
  }
  output.metadata['tasks_runtime'] = enabled;
  if (!enabled || !input.config.buildCodeAssets) return;
  final code = input.config.code;
  if (code.targetOS != OS.macOS ||
      code.targetArchitecture != Architecture.arm64) {
    throw UnsupportedError(
      'The shared MediaPipe 1.0.1 runtime supports macOS arm64, macOS 14+ only.',
    );
  }
  if (code.linkModePreference == LinkModePreference.static) {
    throw UnsupportedError('MediaPipe requires dynamic library bundling.');
  }
  final library = await downloadInteractiveSegmenterLibrary(
    asset: tasksRuntimeArchive,
    cache: Directory.fromUri(
      input.outputDirectoryShared.resolve('macos/arm64/tasks-1.0.1/'),
    ),
  );
  output.dependencies.add(library.uri);
  output.dependencies.add(library.parent.uri.resolve('manifest.json'));
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'tasks_1_0_1.dylib',
      linkMode: DynamicLoadingBundled(),
      file: library.uri,
    ),
  );
});
