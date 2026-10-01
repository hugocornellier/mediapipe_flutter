import 'package:flutter/services.dart';

/// Keeps recently used bundled models in memory across gallery pages.
/// Uploaded models bypass this cache. A small cap avoids retaining the full
/// model catalog on mobile browsers.
abstract final class WebModelCache {
  static const int _maxBytes = 24 * 1024 * 1024;
  static final _models = <String, Uint8List>{};
  static final _loading = <String, Future<Uint8List>>{};
  static int _bytes = 0;
  static Future<void> _prefetches = Future.value();

  static Future<Uint8List> load(String asset) {
    final cached = _models.remove(asset);
    if (cached != null) {
      _models[asset] = cached;
      return Future.value(cached);
    }
    // A page and a prefetch asking at once share one download. The block body
    // matters: returning the removed future would make this one wait on itself.
    return _loading[asset] ??= _fetch(asset).whenComplete(() {
      _loading.remove(asset);
    });
  }

  static Future<Uint8List> _fetch(String asset) async {
    final data = await rootBundle.load(asset);
    final model = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (model.lengthInBytes > _maxBytes) return model;

    while (_bytes + model.lengthInBytes > _maxBytes) {
      final oldest = _models.keys.first;
      _bytes -= _models.remove(oldest)!.lengthInBytes;
    }
    _models[asset] = model;
    _bytes += model.lengthInBytes;
    return model;
  }

  /// Fetches [assets] one at a time once the models already loading are in,
  /// for the pages a visitor is likely to open next.
  static void prefetch(Iterable<String> assets) {
    for (final asset in assets) {
      _prefetches = _prefetches.then((_) async {
        try {
          await Future.wait(_loading.values.toList());
          await load(asset);
        } catch (_) {
          // A page that opens it loads it again and reports the failure.
        }
      });
    }
  }
}
