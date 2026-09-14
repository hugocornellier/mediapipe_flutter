import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'support/classic_text_reference.dart';

void main() {
  late Directory root;
  late File reference;
  late Map<String, dynamic> manifest;
  Future<void> receipt() =>
      File('${root.path}/provenance.json').writeAsString(jsonEncode(manifest));
  Map<String, dynamic> load() => loadClassicTextReference(directory: root.path);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('official-text-test-');
    reference = await File(
      'test/fixtures/classic_text/official_reference.json',
    ).copy('${root.path}/official_reference.json');
    final hash = sha256.convert(await reference.readAsBytes()).toString();
    manifest = {
      'source': 'official-python-api',
      'runtime': 'mediapipe==1.0.1',
      'delegate': 'CPU',
      'library_sha256':
          '9cffc37134d98bdbbcc4b5811d2e2acd66361d05b89761e68a5cb72e0406b53a',
      'wheel_sha256':
          '0a9fb67957f7d28e84f485e9c6716a43367b3f6f07170f31c3f72cac1addd031',
      'reference_sha256': hash,
      'baseline_sha256': hash,
    };
    await receipt();
  });
  tearDown(() => root.delete(recursive: true));

  test('verified host reference preserves every case', () {
    expect(load()['cases'], hasLength(26));
  });

  test(
    'missing reference fails instead of using the checked-in baseline',
    () async {
      await reference.delete();
      expect(load, throwsA(isA<FileSystemException>()));
    },
  );

  test('changed reference bytes are rejected', () async {
    await reference.writeAsString('${await reference.readAsString()} ');
    expect(load, throwsStateError);
  });

  test('a receipt for a different baseline is rejected', () async {
    manifest['baseline_sha256'] = '0' * 64;
    await receipt();
    expect(load, throwsStateError);
  });

  test(
    'wrong model provenance is rejected even with a matching digest',
    () async {
      final data = jsonDecode(await reference.readAsString());
      data['models']['embedder']['sha256'] = '0' * 64;
      await reference.writeAsString(jsonEncode(data));
      manifest['reference_sha256'] = sha256
          .convert(await reference.readAsBytes())
          .toString();
      await receipt();
      expect(load, throwsStateError);
    },
  );
}
