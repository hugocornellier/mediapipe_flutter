/// Verified models shared by every task family: the app's bundled copies,
/// cached on native platforms, and downloads when asked for.
library;

export 'src/download_asset.dart';
export 'src/model_download_exception.dart';
export 'src/model_store_io.dart'
    if (dart.library.js_interop) 'src/model_store_web.dart';
