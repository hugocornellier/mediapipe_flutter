import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_core/native_assets.dart';

/// Bundles Google's MediaPipe library with Decision Maker: its per-family
/// decision library (the delivery of October 8, 2026) on Android, iOS,
/// macOS and Linux, and the library from Google's official 1.1.0 wheel on
/// Windows, which that delivery lacks. Browsers run Google's JavaScript
/// runtime through this package's plugin.
Future<void> main(List<String> args) => build(args, (input, output) async {
  if (!input.config.buildCodeAssets) return;
  if (familyRuntimes['decision']!.containsKey(buildTarget(input.config.code))) {
    await bundleFamilyRuntime(input, output, family: 'decision');
  } else {
    await bundleWheelRuntime(input, output, family: 'decision');
  }
});
