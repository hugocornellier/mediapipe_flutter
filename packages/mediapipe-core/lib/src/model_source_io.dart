import 'download_asset.dart';
import 'model_source.dart';
import 'model_store_io.dart';

/// Resolve a pinned model to its verified native file.
Future<ModelSource> resolvePinnedModel(DownloadAsset model) async =>
    ModelSource(path: (await ModelStore().get(model)).path);
