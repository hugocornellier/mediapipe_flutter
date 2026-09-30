import 'dart:js_interop';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:web/web.dart' as web;

import 'download_asset.dart';
import 'model_download_exception.dart';

/// Verified model bytes in the browser's persistent Cache Storage.
final class ModelStore {
  /// [source] is an internal URL root whose files are named by SHA-256.
  ModelStore({this.source});

  static const _cacheName = 'mediapipe-models-v1';

  /// Internal URL root whose files are named by SHA-256.
  final String? source;
  final Map<String, Future<Uint8List>> _inflight = {};

  String _key(String sha) =>
      Uri.base.resolve('/__mediapipe_models__/$sha').toString();

  /// Returns verified bytes, fetching only when Cache Storage has no valid copy.
  Future<Uint8List> get(DownloadAsset model) =>
      _inflight.putIfAbsent(model.sha256, () async {
        try {
          return await _get(model);
        } finally {
          _inflight.remove(model.sha256);
        }
      });

  Future<Uint8List> _get(DownloadAsset model) async {
    final cache = await web.window.caches.open(_cacheName).toDart;
    final key = _key(model.sha256);
    final cached = await cache.match(key.toJS).toDart;
    if (cached != null) {
      final bytes = (await cached.arrayBuffer().toDart).toDart.asUint8List();
      if (sha256.convert(bytes).toString() == model.sha256) return bytes;
      await cache.delete(key.toJS).toDart;
    }
    final locations = source == null
        ? model.urls
        : [
            Uri.parse(
              source!.endsWith('/') ? source! : '$source/',
            ).resolve(model.sha256).toString(),
          ];
    final failures = <DownloadFailure>[];
    for (final location in locations) {
      try {
        final response = await web.window.fetch(location.toJS).toDart;
        if (!response.ok) throw StateError('HTTP ${response.status}');
        final bytes = (await response.arrayBuffer().toDart).toDart
            .asUint8List();
        final digest = sha256.convert(bytes).toString();
        if (digest != model.sha256) {
          throw StateError(
            'SHA-256 mismatch: expected ${model.sha256}, received $digest',
          );
        }
        await cache.put(key.toJS, web.Response(bytes.toJS)).toDart;
        return bytes;
      } catch (error) {
        failures.add(DownloadFailure(location, error.toString()));
      }
    }
    throw ModelDownloadException(failures, null);
  }

  /// Downloads ahead of task creation.
  Future<void> prefetch(DownloadAsset model) async {
    await get(model);
  }

  /// Removes this library's model entries from Cache Storage.
  Future<void> clear() async {
    await web.window.caches.delete(_cacheName).toDart;
  }
}
