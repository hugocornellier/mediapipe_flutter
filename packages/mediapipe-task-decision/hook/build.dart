import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_core/native_assets.dart';

/// Bundles Google's MediaPipe library with Decision Maker: its per-family
/// decision library on Android, iOS, macOS and Linux, and on Windows, which
/// Google's per-family build lacks, the library from its official 1.1.0
/// wheel (core picks it). Browsers run Google's JavaScript runtime through
/// this package's plugin.
Future<void> main(List<String> args) => build(args, (input, output) async {
  if (!input.config.buildCodeAssets) return;
  await bundleFamilyRuntime(input, output, family: 'decision');
});
