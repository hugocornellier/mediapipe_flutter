import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'download_asset.dart';
import 'model_download_exception.dart';
import 'verified_download.dart';
import 'support_directory_stub.dart'
    if (dart.library.ui) 'support_directory_flutter.dart'
    as support;

/// Models in the application's persistent support directory.
///
/// Native callers receive a file path suitable for MediaPipe task options.
final class ModelStore {
  /// [directory] is useful for tests; the default is application support.
  ModelStore({this.directory, this.source, this.client});

  /// Override for the persistent root, primarily for tests.
  final Directory? directory;

  /// A SHA-named local directory or internal URL root.
  final String? source;

  /// HTTP client override, primarily for tests.
  final http.Client? client;
  final Map<String, Future<File>> _inflight = {};

  Future<Directory> _root() async {
    final root = directory ?? await support.modelsDirectory();
    await root.create(recursive: true);
    if (directory == null) await support.prepareModelsDirectory(root);
    return root;
  }

  /// Downloads on first use, verifies every read, and reuses valid bytes.
  ///
  /// The file keeps the model's original name (MediaPipe can depend on its
  /// extension) inside a folder named by the start of its SHA-256.
  Future<File> get(DownloadAsset model) =>
      _inflight.putIfAbsent(model.sha256, () async {
        try {
          return await _get(model);
        } finally {
          _inflight.remove(model.sha256);
        }
      });

  Future<File> _get(DownloadAsset model) async {
    final root = await _root();
    final name = _folder(model);
    return _withLock(root, name, () async {
      // A verified copy counts whichever pin (and file name) fetched it.
      final folder = Directory.fromUri(root.uri.resolve('$name/'));
      if (await folder.exists()) {
        await for (final entry in folder.list()) {
          if (entry is File &&
              (await sha256.bind(entry.openRead()).first).toString() ==
                  model.sha256) {
            return entry;
          }
        }
      }
      final file = File.fromUri(
        folder.uri.resolve(Uri.parse(model.url).pathSegments.last),
      );
      try {
        return await downloadVerified(
          model,
          file,
          client: client,
          source: source,
        );
      } on DownloadException catch (error) {
        throw ModelDownloadException(error.failures, _networkHint(error));
      }
    });
  }

  /// Prepares a model before task creation, for example on an onboarding page.
  Future<void> prefetch(DownloadAsset model) async {
    await get(model);
  }

  /// Removes every model this store holds, waiting for downloads in progress.
  Future<void> clear() async {
    final root = await _root();
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      await _withLock(root, name, () => entry.delete(recursive: true));
    }
  }

  // Sixteen hex digits keep paths short for Windows' 248-character folders.
  static String _folder(DownloadAsset model) => model.sha256.substring(0, 16);

  // Only a connection failure points at a missing platform permission.
  static String? _networkHint(DownloadException error) {
    final offline = error.failures.any(
      (failure) =>
          failure.reason.contains('SocketException') ||
          failure.reason.contains('ClientException'),
    );
    if (!offline) return null;
    if (Platform.isMacOS) {
      return 'A sandboxed macOS app needs the '
          'com.apple.security.network.client entitlement.';
    }
    if (Platform.isAndroid) {
      return 'Android needs the INTERNET permission in AndroidManifest.xml.';
    }
    return null;
  }

  // One claim file per model, so unrelated models never wait on each other,
  // held across isolates and processes.
  Future<T> _withLock<T>(
    Directory root,
    String name,
    Future<T> Function() body,
  ) async {
    final claim = File.fromUri(root.uri.resolve('$name.lock'));
    while (true) {
      try {
        await claim.create(exclusive: true);
        break;
      } on FileSystemException {
        if (!await claim.exists()) rethrow;
        final age = DateTime.now().difference(await claim.lastModified());
        if (age > const Duration(minutes: 10)) {
          // A crashed process cannot remove its claim. Active owners refresh
          // the timestamp, including during a slow network transfer.
          await claim.delete();
          continue;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    final heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(
        claim.setLastModified(DateTime.now()).catchError((Object _) {}),
      );
    });
    try {
      return await body();
    } finally {
      heartbeat.cancel();
      await claim.delete();
    }
  }
}
