import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Official runtimes a same-host reference may come from, by library digest:
/// the `mediapipe` release and the upstream revision its outputs record.
/// Upstream never tagged 1.0.1, so its references carry no revision.
const _officialRuntimes = <String, (String, String?)>{
  // macOS arm64.
  'aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f': (
    'mediapipe==1.0.0',
    '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120',
  ),
  // Linux x64.
  'b72e6d61a79d1080d29a96ba95e3cfa3e43f6c433c0acc3bc9b3eb7ac0ba103a': (
    'mediapipe==1.0.1',
    null,
  ),
  // Windows x64.
  'a8970c645c8c87c25ec9965cb5c898e803c6c42f7192b7de9a0541c62ae48cef': (
    'mediapipe==1.0.0',
    '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120',
  ),
};

/// The official library this host's native tests load.
String? get _hostLibrary => Platform.isLinux
    ? 'b72e6d61a79d1080d29a96ba95e3cfa3e43f6c433c0acc3bc9b3eb7ac0ba103a'
    : Platform.isWindows
    ? 'a8970c645c8c87c25ec9965cb5c898e803c6c42f7192b7de9a0541c62ae48cef'
    : Platform.isMacOS
    ? 'aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f'
    : null;

/// macOS compares GPU output with its checked-in physical-Mac references, or
/// with same-host ones. Linux has no checked-in GPU references, so it runs the
/// GPU suites only against same-host official outputs.
bool get gpuFaceTestsEnabled =>
    Platform.isMacOS ||
    (Platform.isLinux &&
        Platform.environment['MEDIAPIPE_GPU_REFERENCE_DIR'] != null);

/// Why the GPU face suites are skipped on this host.
const gpuFaceTestsSkipReason =
    'GPU face inference is validated on macOS, and on Linux against '
    'same-host references (MEDIAPIPE_GPU_REFERENCE_DIR).';

/// CPU goldens stay fixed. CI may use GPU outputs from the pinned official wheel
/// on that same host; missing, modified or differently pinned outputs fail.
/// macOS GPU references must confirm Metal, Linux ones an OpenGL ES context.
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
    final expectedLibrary = _hostLibrary;
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
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw StateError('Invalid same-host official GPU reference: $relative');
    }
    _verifyReceipt(
      receipt,
      relative,
      bytes,
      reference,
      'GPU',
      expectedLibrary: _hostLibrary,
      confirmation: Platform.isMacOS ? 'metal_confirmed' : 'gl_confirmed',
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
  String? confirmation,
}) {
  final manifest =
      jsonDecode(receipt.readAsStringSync()) as Map<String, dynamic>;
  final library = expectedLibrary ?? manifest['library_sha256'];
  final runtime = _officialRuntimes[library];
  if (library is! String ||
      runtime == null ||
      manifest['runtime'] != runtime.$1 ||
      manifest['library_sha256'] != library ||
      manifest['source'] != 'official-python-api' ||
      manifest['delegate'] != delegate ||
      (confirmation != null && manifest[confirmation] != true) ||
      manifest['files'] is! Map ||
      (manifest['files'] as Map)[relative] !=
          sha256.convert(bytes).toString() ||
      reference['runtime'] != manifest['runtime'] ||
      reference['library_sha256'] != library ||
      reference['delegate'] != delegate ||
      reference['source_revision'] != runtime.$2) {
    throw StateError(
      'Invalid same-host official $delegate reference: $relative',
    );
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
  final delta = _deltas.putIfAbsent(
    '$task/$delegate/$group',
    _ReferenceDelta.new,
  );
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
