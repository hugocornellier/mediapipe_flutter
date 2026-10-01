import 'package:mediapipe_core/io.dart';
import 'package:mediapipe_core/model_store.dart';
import 'package:mediapipe_core/platform_interface.dart';

import '../models.dart' show TextModels;

/// Converts a verified pin to native classic text base options.
Future<BaseOptions> resolveTextModel(DownloadAsset model) async {
  final source = await resolvePinnedModel(
    model,
    family: 'mediapipe_text',
    registry: TextModels.byName,
  );
  return BaseOptions.path(source.path!);
}
