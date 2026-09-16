import 'dart:async';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:http/http.dart' as http;

/// A reviewed, immutable download and its expected SHA-256 digest.
typedef DownloadAsset = ({String url, String sha256});

/// Downloads [asset] atomically, reusing an existing file only if its hash matches.
/// A failed download never replaces an existing destination.
Future<File> downloadVerified(
  DownloadAsset asset,
  File destination, {
  http.Client? client,
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
  final temporary = await destination.parent.createTemp('.download-');
  final partial = File.fromUri(temporary.uri.resolve('asset'));
  final connection = client ?? http.Client();
  try {
    final response = await connection
        .send(http.Request('GET', Uri.parse(asset.url)))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw HttpException(
        'Download failed: HTTP ${response.statusCode}',
        uri: Uri.parse(asset.url),
      );
    }
    final sink = partial.openWrite();
    try {
      await sink.addStream(
        response.stream.timeout(const Duration(seconds: 60)),
      );
      await sink.flush();
      await sink.close();
    } catch (_) {
      // A stalled or failed response already closed the sink, so closing it
      // again throws `FileSystemException: File closed` and would report that
      // in place of the download failure that actually happened.
      await sink.close().catchError((Object _) {});
      rethrow;
    }
    final digest = (await sha256.bind(partial.openRead()).first).toString();
    if (digest != asset.sha256) {
      throw StateError(
        'SHA-256 mismatch for ${asset.url}: '
        'expected ${asset.sha256}, received $digest',
      );
    }
    await partial.rename(destination.path);
    return destination;
  } finally {
    if (client == null) connection.close();
    await temporary.delete(recursive: true);
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
  await downloadVerified(asset, destination);
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
