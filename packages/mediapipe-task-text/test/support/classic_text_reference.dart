import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// CI compares against Google's pinned CPU runtime on the same host.
/// Missing or modified oracle files fail instead of falling back to a baseline.
Map<String, dynamic> loadClassicTextReference({String? directory}) {
  final baselineBytes = File(
    'test/fixtures/classic_text/official_reference.json',
  ).readAsBytesSync();
  final baseline =
      jsonDecode(utf8.decode(baselineBytes)) as Map<String, dynamic>;
  final override =
      directory ?? Platform.environment['MEDIAPIPE_CLASSIC_TEXT_REFERENCE_DIR'];
  if (override == null) return baseline;
  final root = Directory(override).absolute.uri;
  final bytes = File.fromUri(
    root.resolve('official_reference.json'),
  ).readAsBytesSync();
  final reference = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final receipt =
      jsonDecode(
            File.fromUri(root.resolve('provenance.json')).readAsStringSync(),
          )
          as Map<String, dynamic>;
  if (receipt['source'] != 'official-python-api' ||
      receipt['runtime'] != 'mediapipe==1.0.1' ||
      receipt['delegate'] != 'CPU' ||
      receipt['library_sha256'] !=
          '9cffc37134d98bdbbcc4b5811d2e2acd66361d05b89761e68a5cb72e0406b53a' ||
      receipt['wheel_sha256'] !=
          '0a9fb67957f7d28e84f485e9c6716a43367b3f6f07170f31c3f72cac1addd031' ||
      receipt['reference_sha256'] != sha256.convert(bytes).toString() ||
      receipt['baseline_sha256'] != sha256.convert(baselineBytes).toString() ||
      [
        'runtime',
        'delegate',
        'library_sha256',
        'models',
        'abi',
      ].any((key) => jsonEncode(reference[key]) != jsonEncode(baseline[key]))) {
    throw StateError('Invalid same-host official classic text reference');
  }
  return reference;
}
