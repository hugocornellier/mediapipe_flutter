import 'dart:async';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:http/http.dart' as http;
import '../download_asset.dart';

export '../download_asset.dart';

/// Where build hooks fetch pinned assets instead of their URLs, for offline
/// and mirrored builds: `hooks.user_defines.mediapipe_flutter_core.asset_source`,
/// a directory (relative to the app's pubspec) or an http(s) root holding
/// files named by their SHA-256.
///
/// It is a build setting, not the `MEDIAPIPE_ASSET_SOURCE` environment
/// variable that command-line tools read, because the hook runner passes
/// hooks only an allowlist of variables. Core's hook reads it and forwards it
/// to the family hooks as metadata.
String? hookAssetSource(BuildInput input) {
  if (input.packageName != 'mediapipe_flutter_core') {
    return input.metadata['mediapipe_flutter_core']['asset_source'] as String?;
  }
  final value = input.userDefines['asset_source'];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw const FormatException(
      'mediapipe_flutter_core.asset_source must be a directory or an http(s) '
      'URL.',
    );
  }
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }
  return input.userDefines.path('asset_source')!.toFilePath();
}

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

/// The build target a hook produces assets for: `macos/arm64`,
/// `ios-simulator/arm64`, `ios/arm64`, `linux/x64`, `windows/arm64`, and so on.
///
/// Runtime tables are keyed by this string. The iOS simulator is a separate
/// target because its binaries are built with a different SDK than devices.
String buildTarget(CodeConfig code) {
  final os = code.targetOS;
  final platform = os == OS.iOS && code.iOS.targetSdk == IOSSdk.iPhoneSimulator
      ? 'ios-simulator'
      : os.toString();
  return '$platform/${code.targetArchitecture}';
}

/// Rejects static linking, which no MediaPipe runtime supports.
void requireDynamicLinking(CodeConfig code) {
  if (code.linkModePreference == LinkModePreference.static) {
    throw UnsupportedError('MediaPipe requires dynamic library bundling.');
  }
}

/// Bundles the pinned library for the exact OS, architecture, and Apple SDK.
Future<void> buildNativeLibrary(
  BuildInput input,
  BuildOutputBuilder output, {
  required String assetName,
  required Map<String, Map<String, DownloadAsset>> downloads,
}) async {
  if (!input.config.buildCodeAssets) return;
  final config = input.config.code;
  final os = config.targetOS.toString();
  final architecture = config.targetArchitecture.toString();
  if (config.targetOS == OS.iOS && config.iOS.targetSdk != IOSSdk.iPhoneOS) {
    throw UnsupportedError(
      '${input.packageName} has no iOS simulator runtime. '
      'The pinned iOS library is for arm64 devices only.',
    );
  }
  final asset = downloads[os]?[architecture];
  if (asset == null) {
    final targets = [
      for (final os in downloads.entries)
        for (final arch in os.value.keys) '${os.key}/$arch',
    ].join(', ');
    throw UnsupportedError(
      '${input.packageName} has no runtime for '
      '$os/$architecture. Available artifacts: $targets.',
    );
  }
  if (config.linkModePreference == LinkModePreference.static) {
    throw UnsupportedError(
      '${input.packageName} provides dynamic libraries only.',
    );
  }
  final filename = Uri.parse(asset.url).pathSegments.last;
  final destination = File.fromUri(
    input.outputDirectoryShared.resolve(
      '$os/$architecture/${asset.sha256}/$filename',
    ),
  );
  await downloadVerified(asset, destination, source: hookAssetSource(input));
  output.dependencies.addAll([
    input.packageRoot.resolve('hook/build.dart'),
    input.packageRoot.resolve('sdk_downloads.dart'),
  ]);
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: assetName,
      linkMode: DynamicLoadingBundled(),
      file: destination.uri,
    ),
  );
}
