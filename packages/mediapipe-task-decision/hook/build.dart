import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_core/native_assets.dart';

/// Bundles Google's MediaPipe library with Decision Maker: the library from
/// Google's official 1.1.0 wheel on macOS, Linux and Windows, until Google
/// builds a per-family Decision library. Android and iOS get none yet, and
/// browsers run Google's JavaScript runtime through this package's plugin.
Future<void> main(List<String> args) => build(args, (input, output) async {
  if (!input.config.buildCodeAssets) return;
  await bundleWheelRuntime(input, output, family: 'decision');
});
