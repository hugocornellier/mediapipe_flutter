import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'download_asset.dart';

// Shared by build hooks and the app-side model store, so it depends on
// neither the hooks nor the code_assets package.

/// Downloads [asset] atomically, reusing an existing file only if its hash matches.
/// A failed download never replaces an existing destination.
Future<File> downloadVerified(
  DownloadAsset asset,
  File destination, {
  http.Client? client,
  String? source,
}) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(asset.sha256)) {
    throw ArgumentError.value(asset.sha256, 'sha256', 'Expected SHA-256 hex');
  }
  if (await destination.exists() &&
      (await sha256.bind(destination.openRead()).first).toString() ==
          asset.sha256) {
    return destination;
  }
  await destination.parent.create(recursive: true);
  final configured = source ?? Platform.environment['MEDIAPIPE_ASSET_SOURCE'];
  final locations = configured == null || configured.isEmpty
      ? asset.urls.toList()
      : [
          configured.startsWith('http://') || configured.startsWith('https://')
              ? Uri.parse(
                  '${configured.endsWith('/') ? configured : '$configured/'}${asset.sha256}',
                ).toString()
              : File.fromUri(
                  Directory(configured).uri.resolve(asset.sha256),
                ).uri.toString(),
        ];
  final failures = <DownloadFailure>[];
  final connection = client ?? http.Client();
  try {
    for (final location in locations) {
      final temporary = await destination.parent.createTemp('.download-');
      final partial = File.fromUri(temporary.uri.resolve('asset'));
      try {
        final uri = Uri.parse(location);
        if (uri.scheme == 'file') {
          await File.fromUri(uri).copy(partial.path);
        } else {
          final response = await connection
              .send(http.Request('GET', uri))
              .timeout(const Duration(seconds: 60));
          if (response.statusCode != 200) {
            throw HttpException('HTTP ${response.statusCode}', uri: uri);
          }
          final sink = partial.openWrite();
          try {
            await sink.addStream(
              response.stream.timeout(const Duration(seconds: 60)),
            );
            await sink.flush();
            await sink.close();
          } catch (_) {
            await sink.close().catchError((Object _) {});
            rethrow;
          }
        }
        final digest = (await sha256.bind(partial.openRead()).first).toString();
        if (digest != asset.sha256) {
          throw StateError(
            'SHA-256 mismatch: expected ${asset.sha256}, received $digest',
          );
        }
        await partial.rename(destination.path);
        return destination;
      } catch (error) {
        failures.add(DownloadFailure(location, error.toString()));
      } finally {
        await temporary.delete(recursive: true);
      }
    }
    throw DownloadException(failures);
  } finally {
    if (client == null) connection.close();
  }
}
