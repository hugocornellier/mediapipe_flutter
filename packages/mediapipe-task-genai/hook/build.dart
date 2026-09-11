import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';

import '../sdk_downloads.dart';

Future<void> main(List<String> args) => build(args, (input, output) async {
  await buildNativeLibrary(
    input,
    output,
    assetName:
        'src/io/third_party/mediapipe/generated/mediapipe_flutter_genai_bindings.dart',
    downloads: sdkDownloads,
  );
});
