import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_core/src/native_assets/tasks_runtime.dart';

Future<void> main(List<String> arguments) =>
    build(arguments, (input, output) async {
      final enabled = input.userDefines['tasks_runtime'] ?? false;
      if (enabled is! bool) {
        throw const FormatException(
          'mediapipe_flutter_core.tasks_runtime must be a boolean.',
        );
      }
      output.metadata['tasks_runtime'] = enabled;
      if (!enabled || !input.config.buildCodeAssets) return;
      final code = input.config.code;
      final target = buildTarget(code);
      final release = requireTasksRuntimeRelease(target);
      requireDynamicLinking(code);
      final library = await downloadTasksRuntime(
        release: release,
        cache: Directory.fromUri(
          input.outputDirectoryShared.resolve(
            '$target/tasks-$tasksRuntimeVersion/',
          ),
        ),
      );
      output.dependencies.add(library.uri);
      output.dependencies.add(library.parent.uri.resolve('manifest.json'));
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: tasksRuntimeAssetName,
          linkMode: DynamicLoadingBundled(),
          file: library.uri,
        ),
      );
    });
