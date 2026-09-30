import 'package:mediapipe_core/io.dart';
import 'package:mediapipe_core/model_store.dart';
import 'package:mediapipe_core/platform_interface.dart';

/// Converts a verified pin to native classic text base options.
Future<BaseOptions> resolveTextModel(DownloadAsset model) async {
  final source = await resolvePinnedModel(model);
  return BaseOptions.path(source.path!);
}
