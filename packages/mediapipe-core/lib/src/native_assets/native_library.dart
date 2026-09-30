import 'dart:async';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import '../download_asset.dart';
import '../verified_download.dart';

export '../download_asset.dart';
export '../verified_download.dart';

/// Where build hooks fetch pinned assets instead of their URLs, for offline
/// and mirrored builds: `hooks.user_defines.mediapipe_core.asset_source`,
/// a directory (relative to the app's pubspec) or an http(s) root holding
/// files named by their SHA-256.
///
/// It is a build setting, not the `MEDIAPIPE_ASSET_SOURCE` environment
/// variable that command-line tools read, because the hook runner passes
/// hooks only an allowlist of variables. Core's hook reads it and forwards it
/// to the family hooks as metadata.
String? hookAssetSource(BuildInput input) {
  if (input.packageName != 'mediapipe_core') {
    return input.metadata['mediapipe_core']['asset_source'] as String?;
  }
  final value = input.userDefines['asset_source'];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw const FormatException(
      'mediapipe_core.asset_source must be a directory or an http(s) '
      'URL.',
    );
  }
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }
  return input.userDefines.path('asset_source')!.toFilePath();
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
