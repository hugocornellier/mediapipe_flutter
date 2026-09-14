import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';

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
  if (!legacy) return;
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
