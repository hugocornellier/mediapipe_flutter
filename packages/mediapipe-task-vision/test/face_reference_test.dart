import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'support/face_reference.dart';

void main() {
  late Directory root;
  late File file;
  late Map<String, dynamic> manifest;
  const relative = 'face_detection/official_gpu_reference.json';
  Future<void> receipt() =>
      File('${root.path}/provenance.json').writeAsString(jsonEncode(manifest));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('official-gpu-test-');
    await Directory('${root.path}/face_detection').create();
    file = await File('test/fixtures/$relative').copy('${root.path}/$relative');
    manifest = {
      'source': 'official-python-api',
      'runtime': 'mediapipe==1.0.0',
      'library_sha256':
          'aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f',
      'delegate': 'GPU',
      'metal_confirmed': true,
      'files': {relative: sha256.convert(await file.readAsBytes()).toString()},
    };
    await receipt();
  });
  tearDown(() => root.delete(recursive: true));

  Map<String, dynamic> load() => loadFaceReference(
    'face_detection',
    'official_gpu_reference.json',
    gpuReferenceDirectory: root.path,
  );

  test('verified GPU override retains the independent outputs', () {
    expect(load()['cases'], isNotEmpty);
    expect(load()['delegate'], 'GPU');
  });
  test('CPU always uses checked-in references even with an override', () {
    expect(
      loadFaceReference(
        'face_detection',
        'official_reference.json',
        gpuReferenceDirectory: '/does/not/exist',
      )['delegate'],
      'CPU',
    );
  });
  test(
    'missing GPU output fails instead of falling back to another host',
    () async {
      await file.delete();
      expect(load, throwsA(isA<FileSystemException>()));
    },
  );
  test(
    'modified GPU results and missing Metal provenance are rejected',
    () async {
      final original = await file.readAsString();
      await file.writeAsString('$original ');
      expect(load, throwsStateError);
      await file.writeAsString(original);
      manifest['metal_confirmed'] = false;
      await receipt();
      expect(load, throwsStateError);
    },
  );
  test(
    'wrong official runtime is rejected even with a matching file digest',
    () async {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      data['library_sha256'] = '0' * 64;
      await file.writeAsString(jsonEncode(data));
      manifest['files'] = {
        relative: sha256.convert(await file.readAsBytes()).toString(),
      };
      await receipt();
      expect(load, throwsStateError);
    },
  );
}
