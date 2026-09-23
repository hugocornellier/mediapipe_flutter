@TestOn('mac-os || linux')
library;

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
  // Same-host GPU references exist on macOS (Metal) and Linux (OpenGL ES).
  final (runtime, library, revision, confirmation) = Platform.isLinux
      ? (
          'mediapipe==1.0.1',
          'b72e6d61a79d1080d29a96ba95e3cfa3e43f6c433c0acc3bc9b3eb7ac0ba103a',
          null,
          'gl_confirmed',
        )
      : (
          'mediapipe==1.0.0',
          'aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f',
          '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120',
          'metal_confirmed',
        );
  Future<void> receipt() =>
      File('${root.path}/provenance.json').writeAsString(jsonEncode(manifest));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('official-gpu-test-');
    await Directory('${root.path}/face_detection').create();
    // Stand in for this host's official output: the checked-in macOS results
    // relabeled with the runtime this host's receipt must name.
    final data =
        jsonDecode(await File('test/fixtures/$relative').readAsString())
            as Map<String, dynamic>;
    data
      ..['runtime'] = runtime
      ..['library_sha256'] = library
      ..['source_revision'] = revision;
    file = File('${root.path}/$relative');
    await file.writeAsString(jsonEncode(data));
    manifest = {
      'source': 'official-python-api',
      'runtime': runtime,
      'library_sha256': library,
      'delegate': 'GPU',
      confirmation: true,
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
    'modified GPU results and missing GPU provenance are rejected',
    () async {
      final original = await file.readAsString();
      await file.writeAsString('$original ');
      expect(load, throwsStateError);
      await file.writeAsString(original);
      manifest[confirmation] = false;
      await receipt();
      expect(load, throwsStateError);
    },
  );
  test('the other host\'s GPU confirmation is not accepted', () async {
    manifest
      ..remove(confirmation)
      ..[confirmation == 'gl_confirmed' ? 'metal_confirmed' : 'gl_confirmed'] =
          true;
    await receipt();
    expect(load, throwsStateError);
  });
  test('a reference claiming another runtime version is rejected', () async {
    manifest['runtime'] = runtime == 'mediapipe==1.0.1'
        ? 'mediapipe==1.0.0'
        : 'mediapipe==1.0.1';
    await receipt();
    expect(load, throwsStateError);
  });
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
