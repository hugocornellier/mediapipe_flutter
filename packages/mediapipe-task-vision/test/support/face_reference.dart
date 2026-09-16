import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// CPU goldens stay fixed. CI may use GPU outputs from the pinned official wheel
/// on that same host; missing, modified or differently pinned outputs fail.
Map<String, dynamic> loadFaceReference(
  String task,
  String filename, {
  String? gpuReferenceDirectory,
}) {
  final gpu = filename.contains('_gpu_');
  final override =
      gpuReferenceDirectory ??
      Platform.environment['MEDIAPIPE_GPU_REFERENCE_DIR'];
  final cpuOverride = Platform.environment['MEDIAPIPE_CPU_REFERENCE_DIR'];
  final root = !gpu && cpuOverride != null
      ? Directory(cpuOverride).absolute
      : gpu && override != null
      ? Directory(override).absolute
      : Directory('test/fixtures').absolute;
  final relative = '$task/$filename';
  final bytes = File.fromUri(root.uri.resolve(relative)).readAsBytesSync();
  final reference = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  if (!gpu && cpuOverride != null) {
    final manifest =
        jsonDecode(
              File.fromUri(
                root.uri.resolve('provenance.json'),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final expectedLibrary = Platform.isLinux
        ? '35ef4187d381addb1309f0f9dedd32613127fa98d1ad1f5ddeea57595cdbcaf0'
        : Platform.isWindows
        ? 'a8970c645c8c87c25ec9965cb5c898e803c6c42f7192b7de9a0541c62ae48cef'
        : null;
    if (expectedLibrary == null ||
        manifest['runtime'] != 'mediapipe==1.0.0' ||
        manifest['library_sha256'] != expectedLibrary ||
        manifest['source'] != 'official-python-api' ||
        manifest['delegate'] != 'CPU' ||
        manifest['files'] is! Map ||
        (manifest['files'] as Map)[relative] !=
            sha256.convert(bytes).toString() ||
        reference['runtime'] != manifest['runtime'] ||
        reference['library_sha256'] != expectedLibrary ||
        reference['delegate'] != 'CPU' ||
        reference['source_revision'] !=
            '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120') {
      throw StateError('Invalid same-host official CPU reference: $relative');
    }
  }
  if (gpu && override != null) {
    final manifest =
        jsonDecode(
              File.fromUri(
                root.uri.resolve('provenance.json'),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    if (manifest['runtime'] != 'mediapipe==1.0.0' ||
        manifest['library_sha256'] !=
            'aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f' ||
        manifest['source'] != 'official-python-api' ||
        manifest['delegate'] != 'GPU' ||
        manifest['metal_confirmed'] != true ||
        manifest['files'] is! Map ||
        (manifest['files'] as Map)[relative] !=
            sha256.convert(bytes).toString() ||
        reference['runtime'] != manifest['runtime'] ||
        reference['library_sha256'] != manifest['library_sha256'] ||
        reference['delegate'] != 'GPU' ||
        reference['source_revision'] !=
            '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120') {
      throw StateError('Invalid same-host official GPU reference: $relative');
    }
  }
  return reference;
}
