import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';

/// Bundle filename for the official runtime with adjusted loader metadata.
const interactiveSegmenterLibraryName = 'libinteractive_segmenter.dylib';

/// SHA-256 of the prepared library, before Flutter's final bundling/signing.
const interactiveSegmenterLibrarySha256 =
    '31acd66d5fba204bce929ccdf7a57894a3a6afdf57d3d95b062bcf6c40178db4';
const _wheelSha256 =
    '0a9fb67957f7d28e84f485e9c6716a43367b3f6f07170f31c3f72cac1addd031';
const _files = {
  interactiveSegmenterLibraryName: interactiveSegmenterLibrarySha256,
  'LICENSE': '8707eef0533987efc5b155d64761eeb6e20793f50b9bd1a68dad1cf4719d0ed8',
  'NOTICE': 'e8e3eddc5c36d7413635455933650d7423b937185180e393f9a006bee60162e7',
};

/// Validates the official prebuilt distribution independently of source builds.
Future<File> validateInteractiveSegmenterLibrary(Directory directory) async {
  final manifest = jsonDecode(
    await File.fromUri(directory.uri.resolve('manifest.json')).readAsString(),
  );
  if (manifest is! Map<String, dynamic> ||
      manifest['origin'] != 'official-pypi-wheel' ||
      manifest['upstream_version'] != '1.0.1' ||
      manifest['upstream_sha256'] != _wheelSha256 ||
      manifest['upstream_library'] != 'mediapipe/tasks/c/libmediapipe.dylib' ||
      manifest['upstream_library_sha256'] !=
          '9cffc37134d98bdbbcc4b5811d2e2acd66361d05b89761e68a5cb72e0406b53a' ||
      manifest['release'] != 'interactive-segmenter-v1.0.1-1' ||
      manifest['platform'] != 'macos' ||
      manifest['architecture'] != 'arm64' ||
      manifest['minimum_os'] != '14.0' ||
      manifest['sha256'] != interactiveSegmenterLibrarySha256 ||
      manifest['bytes'] != 100946816 ||
      manifest['delegates'] is! List ||
      (manifest['delegates'] as List).length != 1 ||
      (manifest['delegates'] as List).single != 'cpu') {
    throw StateError('Interactive Segmenter runtime provenance mismatch.');
  }
  if (manifest['files'] is! Map ||
      manifest['packaging'] is! Map ||
      manifest['packaging']['unchanged_payload_sha256'] !=
          'abd869fade4cb65a9964d8fdba2b8df982c3cac3f8e2e15bfccdc6fd5fa85550' ||
      manifest['packaging']['section_layout_unchanged'] != true) {
    throw StateError('Interactive Segmenter packaging provenance mismatch.');
  }
  for (final entry in _files.entries) {
    final file = File.fromUri(directory.uri.resolve(entry.key));
    if ((manifest['files'] as Map?)?[entry.key] != entry.value ||
        (await sha256.bind(file.openRead()).first).toString() != entry.value) {
      throw StateError(
        'Interactive Segmenter runtime checksum mismatch: ${entry.key}',
      );
    }
  }
  final library = File.fromUri(
    directory.uri.resolve(interactiveSegmenterLibraryName),
  );
  if (await library.length() != manifest['bytes']) {
    throw StateError('Interactive Segmenter runtime size mismatch.');
  }
  return library;
}

/// Download only when the consuming app explicitly selects this task.
Future<File> downloadInteractiveSegmenterLibrary({
  required DownloadAsset asset,
  required Directory cache,
}) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(asset.sha256)) {
    throw ArgumentError('Expected an archive SHA-256 digest.');
  }
  final directory = Directory.fromUri(cache.uri.resolve('${asset.sha256}/'));
  final compressed = File.fromUri(directory.uri.resolve('runtime.tar.gz'));
  await downloadVerified(asset, compressed);
  try {
    return await validateInteractiveSegmenterLibrary(directory);
  } on FileSystemException {
    // Incomplete extraction is repaired from the verified archive.
  } on FormatException {
    // A corrupt manifest is repaired from the verified archive.
  } on StateError {
    // Never return modified cached bytes.
  }
  final temporary = await directory.createTemp('.unpack-');
  try {
    final allowed = {..._files.keys, 'manifest.json'};
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
      throw const FormatException(
        'Interactive Segmenter archive is incomplete.',
      );
    }
    for (final entry in archive) {
      await File.fromUri(
        temporary.uri.resolve(entry.name),
      ).writeAsBytes(entry.readBytes()!);
    }
    await validateInteractiveSegmenterLibrary(temporary);
    // Publish the library last; concurrent extractions contain identical bytes.
    for (final name in allowed.where(
      (name) => name != interactiveSegmenterLibraryName,
    )) {
      await File.fromUri(
        temporary.uri.resolve(name),
      ).rename(File.fromUri(directory.uri.resolve(name)).path);
    }
    return await File.fromUri(
      temporary.uri.resolve(interactiveSegmenterLibraryName),
    ).rename(
      File.fromUri(directory.uri.resolve(interactiveSegmenterLibraryName)).path,
    );
  } finally {
    await temporary.delete(recursive: true);
  }
}
