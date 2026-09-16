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
  final receipt = File.fromUri(root.uri.resolve('provenance.json'));
  if (!gpu && cpuOverride != null) {
    final expectedLibrary = Platform.isLinux
        ? '35ef4187d381addb1309f0f9dedd32613127fa98d1ad1f5ddeea57595cdbcaf0'
        : Platform.isWindows
        ? 'a8970c645c8c87c25ec9965cb5c898e803c6c42f7192b7de9a0541c62ae48cef'
        : null;
    if (expectedLibrary == null) {
      throw StateError('Invalid same-host official CPU reference: $relative');
    }
    _verifyReceipt(
      receipt,
      relative,
      bytes,
      reference,
      'CPU',
      expectedLibrary: expectedLibrary,
    );
  }
  // A packaged mobile consumer reads its references from bundled assets and
  // cannot see an environment variable, so its runner substitutes the host
  // reference in place and ships the same receipt beside it. The host verifies
  // the library digest against the pinned wheel row before substituting.
  if (!gpu && cpuOverride == null && receipt.existsSync()) {
    _verifyReceipt(receipt, relative, bytes, reference, 'CPU');
  }
  if (gpu && override != null) {
    _verifyReceipt(
      receipt,
      relative,
      bytes,
      reference,
      'GPU',
      expectedLibrary:
          'aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f',
      metal: true,
    );
  }
  return reference;
}

void _verifyReceipt(
  File receipt,
  String relative,
  List<int> bytes,
  Map<String, dynamic> reference,
  String delegate, {
  String? expectedLibrary,
  bool metal = false,
}) {
  final manifest =
      jsonDecode(receipt.readAsStringSync()) as Map<String, dynamic>;
  final library = expectedLibrary ?? manifest['library_sha256'];
  if (library is! String ||
      manifest['runtime'] != 'mediapipe==1.0.0' ||
      manifest['library_sha256'] != library ||
      manifest['source'] != 'official-python-api' ||
      manifest['delegate'] != delegate ||
      (metal && manifest['metal_confirmed'] != true) ||
      manifest['files'] is! Map ||
      (manifest['files'] as Map)[relative] != sha256.convert(bytes).toString() ||
      reference['runtime'] != manifest['runtime'] ||
      reference['library_sha256'] != library ||
      reference['delegate'] != delegate ||
      reference['source_revision'] !=
          '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120') {
    throw StateError('Invalid same-host official $delegate reference: $relative');
  }
}

class _ReferenceDelta {
  double maximumAbsoluteError = 0;
  int values = 0;
  String? path;
  num? official;
  num? measured;
}

final Map<String, _ReferenceDelta> _deltas = {};

/// Records how far a native result sits from the official value it is checked
/// against. Suites still apply their unchanged tolerances; this only lets a CI
/// receipt report the measured headroom rather than the first value to exceed
/// one.
void recordReferenceDelta(
  String task,
  String delegate,
  String group,
  String path,
  num measured,
  num official,
) {
  final delta = _deltas.putIfAbsent('$task/$delegate/$group', _ReferenceDelta.new);
  final error = (measured - official).abs().toDouble();
  delta.values++;
  if (error > delta.maximumAbsoluteError) {
    delta
      ..maximumAbsoluteError = error
      ..path = path
      ..official = official
      ..measured = measured;
  }
}

/// Prints one machine-readable line per task; mobile runners copy it into their
/// validation report. Clearing lets combined suites report each task separately.
void reportReferenceDeltas(String task) {
  final prefix = '$task/';
  final keys = _deltas.keys.where((key) => key.startsWith(prefix)).toList()
    ..sort();
  if (keys.isEmpty) return;
  final summary = <String, Map<String, Map<String, Object?>>>{};
  for (final key in keys) {
    final parts = key.substring(prefix.length).split('/');
    final delta = _deltas.remove(key)!;
    summary.putIfAbsent(parts[0], () => {})[parts[1]] = {
      'maximum_absolute_error': delta.maximumAbsoluteError,
      'values': delta.values,
      'path': delta.path,
      'official': delta.official,
      'measured': delta.measured,
    };
  }
  print('MEDIAPIPE_REFERENCE_DELTAS $task ${jsonEncode(summary)}');
}
