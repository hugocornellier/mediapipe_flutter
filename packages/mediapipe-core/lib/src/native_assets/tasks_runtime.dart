import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import '../../native_assets.dart';

/// One native asset shared by modern text tasks and stateful MagicTouch.
///
/// The identifier is stable across platforms; the bundled file name comes from
/// each release's [TasksRuntimeRelease.libraryName].
const tasksRuntimeAssetId = 'package:mediapipe_flutter_core/tasks_1_0_1.dylib';

/// The asset name registered by the core build hook, without the package.
const tasksRuntimeAssetName = 'tasks_1_0_1.dylib';

/// Upstream version every release in [tasksRuntimeReleases] is repackaged from.
const tasksRuntimeVersion = '1.0.1';

/// Loader-metadata adjustments recorded by the packaging tool. Code and data
/// bytes are verified unchanged; only load commands and signing differ.
typedef TasksRuntimePackaging = ({
  String unchangedPayloadSha256,
  bool sectionLayoutUnchanged,
});

/// A pinned, immutable runtime release for one build target.
///
/// Every field is compared against the archive's `manifest.json` and file
/// digests before a library is bundled. Supporting another platform means
/// adding a row to [tasksRuntimeReleases] and publishing its archive; the
/// build hook needs no changes.
final class TasksRuntimeRelease {
  /// Describe a published release. All digests are SHA-256 hex.
  const TasksRuntimeRelease({
    required this.target,
    required this.release,
    required this.archive,
    required this.libraryName,
    required this.librarySha256,
    required this.bytes,
    required this.minimumOs,
    required this.delegates,
    required this.wheelSha256,
    required this.upstreamLibrary,
    required this.upstreamLibrarySha256,
    required this.notices,
    this.packaging,
  });

  /// Build target such as `macos/arm64`; see `buildTarget`.
  final String target;

  /// Release tag in the public native runtime repository.
  final String release;

  /// The archive holding the library, its notices and `manifest.json`.
  final DownloadAsset archive;

  /// Bundle filename of the prepared library.
  final String libraryName;

  /// SHA-256 of the prepared library, before Flutter's final bundling/signing.
  final String librarySha256;

  /// Exact library size, checked before and after extraction.
  final int bytes;

  /// Minimum operating system version recorded by the packaging tool.
  final String minimumOs;

  /// Delegates validated for this release, for example `['cpu']`.
  final List<String> delegates;

  /// SHA-256 of Google's official wheel the library was taken from.
  final String wheelSha256;

  /// Path of the library inside that wheel.
  final String upstreamLibrary;

  /// SHA-256 of the unmodified upstream library.
  final String upstreamLibrarySha256;

  /// License and notice files shipped in the archive, with their digests.
  final Map<String, String> notices;

  /// Expected loader-metadata packaging record, or null when the platform's
  /// library is shipped byte-for-byte as extracted from the wheel.
  final TasksRuntimePackaging? packaging;

  /// Every file the archive must contain, with its digest.
  Map<String, String> get files => {...notices, libraryName: librarySha256};

  /// The platform half of [target].
  String get platform => target.split('/').first;

  /// The architecture half of [target].
  String get architecture => target.split('/').last;

  /// The same release served from another location, for loopback tests.
  TasksRuntimeRelease withArchive(DownloadAsset archive) => TasksRuntimeRelease(
    target: target,
    release: release,
    archive: archive,
    libraryName: libraryName,
    librarySha256: librarySha256,
    bytes: bytes,
    minimumOs: minimumOs,
    delegates: delegates,
    wheelSha256: wheelSha256,
    upstreamLibrary: upstreamLibrary,
    upstreamLibrarySha256: upstreamLibrarySha256,
    notices: notices,
    packaging: packaging,
  );
}

/// Google's complete 1.0.1 task runtime, repackaged per build target.
///
/// Each row is immutable: a rebuild gets a new release tag and new digests.
/// The macOS filename retains its historical segmenter name to preserve the
/// published bytes.
const tasksRuntimeReleases = <String, TasksRuntimeRelease>{
  'macos/arm64': TasksRuntimeRelease(
    target: 'macos/arm64',
    release: 'interactive-segmenter-v1.0.1-1',
    archive: (
      url:
          'https://github.com/hugocornellier/mediapipe_flutter_native/releases/'
          'download/interactive-segmenter-v1.0.1-1/'
          'mediapipe-interactive-segmenter-1.0.1-macos-arm64.tar.gz',
      sha256:
          '8bec2f56b2f6bf2fa0b31dacc0c84110c24174467d2ab131935c85c89a0e5b14',
    ),
    libraryName: 'libinteractive_segmenter.dylib',
    librarySha256:
        '31acd66d5fba204bce929ccdf7a57894a3a6afdf57d3d95b062bcf6c40178db4',
    bytes: 100946816,
    minimumOs: '14.0',
    delegates: ['cpu'],
    wheelSha256:
        '0a9fb67957f7d28e84f485e9c6716a43367b3f6f07170f31c3f72cac1addd031',
    upstreamLibrary: 'mediapipe/tasks/c/libmediapipe.dylib',
    upstreamLibrarySha256:
        '9cffc37134d98bdbbcc4b5811d2e2acd66361d05b89761e68a5cb72e0406b53a',
    notices: {
      'LICENSE':
          '8707eef0533987efc5b155d64761eeb6e20793f50b9bd1a68dad1cf4719d0ed8',
      'NOTICE':
          'e8e3eddc5c36d7413635455933650d7423b937185180e393f9a006bee60162e7',
    },
    packaging: (
      unchangedPayloadSha256:
          'abd869fade4cb65a9964d8fdba2b8df982c3cac3f8e2e15bfccdc6fd5fa85550',
      sectionLayoutUnchanged: true,
    ),
  ),
};

/// The release for [target], or an [UnsupportedError] naming the targets that
/// have one.
TasksRuntimeRelease requireTasksRuntimeRelease(String target) {
  final release = tasksRuntimeReleases[target];
  if (release == null) {
    throw UnsupportedError(
      'The shared MediaPipe $tasksRuntimeVersion runtime has no release for '
      '$target. Available targets: ${tasksRuntimeReleases.keys.join(', ')}.',
    );
  }
  return release;
}

/// Validates an extracted release independently of source builds.
Future<File> validateTasksRuntime(
  Directory directory, {
  required TasksRuntimeRelease release,
}) async {
  final manifest = jsonDecode(
    await File.fromUri(directory.uri.resolve('manifest.json')).readAsString(),
  );
  if (manifest is! Map<String, dynamic> ||
      manifest['origin'] != 'official-pypi-wheel' ||
      manifest['upstream_version'] != tasksRuntimeVersion ||
      manifest['upstream_sha256'] != release.wheelSha256 ||
      manifest['upstream_library'] != release.upstreamLibrary ||
      manifest['upstream_library_sha256'] != release.upstreamLibrarySha256 ||
      manifest['release'] != release.release ||
      manifest['platform'] != release.platform ||
      manifest['architecture'] != release.architecture ||
      manifest['minimum_os'] != release.minimumOs ||
      manifest['sha256'] != release.librarySha256 ||
      manifest['bytes'] != release.bytes ||
      manifest['delegates'] is! List ||
      !_sameList(manifest['delegates'] as List, release.delegates)) {
    throw StateError('${release.target} runtime provenance mismatch.');
  }
  final packaging = release.packaging;
  if (manifest['files'] is! Map ||
      (packaging == null
          ? manifest.containsKey('packaging')
          : manifest['packaging'] is! Map ||
                manifest['packaging']['unchanged_payload_sha256'] !=
                    packaging.unchangedPayloadSha256 ||
                manifest['packaging']['section_layout_unchanged'] !=
                    packaging.sectionLayoutUnchanged)) {
    throw StateError(
      '${release.target} runtime packaging provenance mismatch.',
    );
  }
  for (final entry in release.files.entries) {
    final file = File.fromUri(directory.uri.resolve(entry.key));
    if ((manifest['files'] as Map)[entry.key] != entry.value ||
        (await sha256.bind(file.openRead()).first).toString() != entry.value) {
      throw StateError(
        '${release.target} runtime checksum mismatch: ${entry.key}',
      );
    }
  }
  final library = File.fromUri(directory.uri.resolve(release.libraryName));
  if (await library.length() != release.bytes) {
    throw StateError('${release.target} runtime size mismatch.');
  }
  return library;
}

bool _sameList(List actual, List<String> expected) =>
    actual.length == expected.length &&
    [
      for (var i = 0; i < actual.length; i++) actual[i] == expected[i],
    ].every((equal) => equal);

/// Downloads, verifies and extracts [release] into [cache], reusing a valid
/// extraction and repairing a damaged one from the verified archive.
Future<File> downloadTasksRuntime({
  required TasksRuntimeRelease release,
  required Directory cache,
}) async {
  final asset = release.archive;
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(asset.sha256)) {
    throw ArgumentError('Expected an archive SHA-256 digest.');
  }
  final directory = Directory.fromUri(cache.uri.resolve('${asset.sha256}/'));
  final compressed = File.fromUri(directory.uri.resolve('runtime.tar.gz'));
  await downloadVerified(asset, compressed);
  try {
    return await validateTasksRuntime(directory, release: release);
  } on FileSystemException {
    // Incomplete extraction is repaired from the verified archive.
  } on FormatException {
    // A corrupt manifest is repaired from the verified archive.
  } on StateError {
    // Never return modified cached bytes.
  }
  final temporary = await directory.createTemp('.unpack-');
  try {
    final allowed = {...release.files.keys, 'manifest.json'};
    final seen = <String>{};
    final archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(await compressed.readAsBytes()),
      callback: (entry) {
        if (!entry.isFile ||
            entry.isSymbolicLink ||
            !allowed.contains(entry.name) ||
            !seen.add(entry.name)) {
          throw FormatException(
            'Unexpected native archive entry: ${entry.name}',
          );
        }
      },
    );
    if (!seen.containsAll(allowed)) {
      throw FormatException('${release.target} runtime archive is incomplete.');
    }
    for (final entry in archive) {
      await File.fromUri(
        temporary.uri.resolve(entry.name),
      ).writeAsBytes(entry.readBytes()!);
    }
    await validateTasksRuntime(temporary, release: release);
    // Publish the library last; concurrent extractions contain identical bytes.
    for (final name in allowed.where((name) => name != release.libraryName)) {
      await File.fromUri(
        temporary.uri.resolve(name),
      ).rename(File.fromUri(directory.uri.resolve(name)).path);
    }
    return await File.fromUri(
      temporary.uri.resolve(release.libraryName),
    ).rename(File.fromUri(directory.uri.resolve(release.libraryName)).path);
  } finally {
    await temporary.delete(recursive: true);
  }
}
