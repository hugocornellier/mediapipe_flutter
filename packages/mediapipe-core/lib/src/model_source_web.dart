import 'download_asset.dart';
import 'model_source.dart';
import 'model_store_web.dart';

/// Resolve a pinned model to verified browser bytes.
Future<ModelSource> resolvePinnedModel(DownloadAsset model) async =>
    ModelSource(bytes: await ModelStore().get(model));
