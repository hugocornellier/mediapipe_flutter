import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';

const _mediaPipeRevision = '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120';
const _openCvRevision = '49486f61fb25722cbcf586b7f4320921d46fb38e';

/// Supported native artifact targets. Simulator and device ARM64 are distinct.
enum VisionLibraryTarget {
  /// macOS runtime with CPU and Metal support.
  macosArm64,

  /// iOS simulator runtime with CPU support, built with the simulator SDK.
  iosSimulatorArm64,
}

/// The validation target for a hook build target string; see `buildTarget`.
VisionLibraryTarget visionLibraryTarget(String target) => switch (target) {
  'macos/arm64' => VisionLibraryTarget.macosArm64,
  'ios-simulator/arm64' => VisionLibraryTarget.iosSimulatorArm64,
  _ => throw UnsupportedError(
    'mediapipe_flutter_vision has no native runtime validation for $target.',
  ),
};

Set<String> _requiredFiles(String libraryName) => {
  libraryName,
  'manifest.json',
  'LICENSE',
  'NOTICE',
  'opencv-licenses/LICENSE',
  'opencv-licenses/CAROTENE_NOTICES',
};

/// Checks both provenance and the library bytes before loading native code.
/// Source builds use their manifest digest; downloads also require a pinned
/// digest independent of the downloaded manifest.
Future<File> validateVisionLibrary(
  Directory directory, {
  String? expectedSha256,
  String libraryName = 'libface_detector.dylib',
  VisionLibraryTarget target = VisionLibraryTarget.macosArm64,
}) async {
  _checkLibraryName(libraryName);
  final library = File.fromUri(directory.uri.resolve(libraryName));
  final manifestFile = File.fromUri(directory.uri.resolve('manifest.json'));
  final manifest = jsonDecode(await manifestFile.readAsString());
  final simulator = target == VisionLibraryTarget.iosSimulatorArm64;
  if (manifest is! Map<String, dynamic> ||
      manifest['revision'] != _mediaPipeRevision ||
      manifest['opencv_revision'] != _openCvRevision ||
      manifest['platform'] != (simulator ? 'ios' : 'macos') ||
      manifest['architecture'] != 'arm64' ||
      (simulator && manifest['ios_sdk'] != 'iphonesimulator') ||
      (!simulator && manifest['ios_sdk'] != null) ||
      manifest['bytes'] != await library.length() ||
      (expectedSha256 != null && manifest['sha256'] != expectedSha256) ||
      (await sha256.bind(library.openRead()).first).toString() !=
          manifest['sha256']) {
    throw StateError('MediaPipe native artifact provenance/hash mismatch.');
  }
  final delegates = manifest['delegates'];
  if (delegates is! List ||
      !delegates.contains('cpu') ||
      (!simulator && !delegates.contains('gpu'))) {
    throw StateError(
      simulator
          ? 'The iOS simulator requires a CPU runtime. '
                'Build it with tool/build_ios_simulator.py.'
          : 'This package requires a CPU and Metal runtime. Rebuild the local '
                'native library without --cpu-only, or use prebuilt: true.',
    );
  }
  return library;
}

/// Downloads and unpacks a pinned runtime using Dart, with no native compiler,
/// shell archive utility, or GitHub credentials required.
Future<File> downloadVisionLibrary({
  required DownloadAsset asset,
  required String librarySha256,
  required Directory cache,
  String libraryName = 'libface_detector.dylib',
  VisionLibraryTarget target = VisionLibraryTarget.macosArm64,
}) async {
  _checkLibraryName(libraryName);
  final requiredFiles = _requiredFiles(libraryName);
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(asset.sha256) ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(librarySha256)) {
    throw ArgumentError('Expected SHA-256 hex digests for the native runtime.');
  }
  final directory = Directory.fromUri(cache.uri.resolve('${asset.sha256}/'));
  final archiveFile = File.fromUri(directory.uri.resolve('runtime.tar.gz'));
  // Validate the compressed cache too, repairing it through downloadVerified.
  await downloadVerified(asset, archiveFile);
  try {
    final library = await validateVisionLibrary(
      directory,
      expectedSha256: librarySha256,
      libraryName: libraryName,
      target: target,
    );
    if (await Future.wait([
      for (final name in requiredFiles)
        File.fromUri(directory.uri.resolve(name)).exists(),
    ]).then((exists) => exists.every((value) => value))) {
      return library;
    }
  } on FileSystemException {
    // Missing or interrupted extraction; recover from the verified archive.
  } on FormatException {
    // A damaged cached manifest can be recovered the same way.
  } on StateError {
    // Never load modified cache contents; replace them from the pinned archive.
  }

  final temporary = await directory.createTemp('.unpack-');
  try {
    final seen = <String>{};
    final archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(await archiveFile.readAsBytes()),
      callback: (entry) {
        final name = entry.name;
        final parts = name.split('/');
        final license =
            parts.length == 2 &&
            parts.first == 'opencv-licenses' &&
            RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(parts.last) &&
            parts.last != '.' &&
            parts.last != '..';
        if (!entry.isFile ||
            entry.isSymbolicLink ||
            !seen.add(name) ||
            !(requiredFiles.contains(name) || license)) {
          throw FormatException('Unexpected native archive entry: $name');
        }
      },
    );
    if (!seen.containsAll(requiredFiles)) {
      throw const FormatException('Native archive is missing required files.');
    }
    // We write only individually validated file names and never follow archive
    // links or ask a general-purpose extractor to choose destination paths.
    for (final entry in archive) {
      final file = File.fromUri(temporary.uri.resolve(entry.name));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.readBytes()!);
    }
    await validateVisionLibrary(
      temporary,
      expectedSha256: librarySha256,
      libraryName: libraryName,
      target: target,
    );
    // Publish the library last. Each rename is atomic and concurrent hooks
    // write identical content within this digest-specific cache directory.
    for (final entry in archive.where((entry) => entry.name != libraryName)) {
      final destination = File.fromUri(directory.uri.resolve(entry.name));
      await destination.parent.create(recursive: true);
      await File.fromUri(
        temporary.uri.resolve(entry.name),
      ).rename(destination.path);
    }
    return await File.fromUri(
      temporary.uri.resolve(libraryName),
    ).rename(File.fromUri(directory.uri.resolve(libraryName)).path);
  } finally {
    await temporary.delete(recursive: true);
  }
}

/// Names a vision runtime may have. This is a closed set so a release row can
/// never name an arbitrary path inside an extracted archive.
const _libraryNames = {
  'libface_detector.dylib',
  'libface_landmarker.dylib',
  // The combined source build covering every open-source task.
  'libmediapipe.dylib',
};

void _checkLibraryName(String name) {
  if (!_libraryNames.contains(name)) {
    throw ArgumentError.value(
      name,
      'libraryName',
      'Unsupported vision runtime',
    );
  }
}
