import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/vision_library.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File library;
  late OfficialWheelProvenance provenance;
  final libraryBytes = utf8.encode('official library');
  final licenseBytes = utf8.encode('official license');
  final noticeBytes = utf8.encode('official notice');
  final libraryHash = sha256.convert(libraryBytes).toString();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'official-landmark-runtime-',
    );
    library = File.fromUri(directory.uri.resolve('libmediapipe.dylib'));
    await library.writeAsBytes(libraryBytes);
    await File.fromUri(
      directory.uri.resolve('LICENSE'),
    ).writeAsBytes(licenseBytes);
    await File.fromUri(
      directory.uri.resolve('NOTICE'),
    ).writeAsBytes(noticeBytes);
    provenance = OfficialWheelProvenance(
      version: '1.0.0',
      wheel: (url: 'https://example.test/mediapipe.whl', sha256: '1' * 64),
      libraryPath: 'mediapipe/tasks/c/libmediapipe.dylib',
      librarySha256: '2' * 64,
      minimumOS: '14.0',
      delegates: const {'cpu', 'gpu'},
      notices: {
        'LICENSE': sha256.convert(licenseBytes).toString(),
        'NOTICE': sha256.convert(noticeBytes).toString(),
      },
    );
    await File.fromUri(directory.uri.resolve('manifest.json')).writeAsString(
      jsonEncode({
        'origin': 'official-pypi-wheel',
        'upstream_version': provenance.version,
        'upstream_url': provenance.wheel.url,
        'upstream_sha256': provenance.wheel.sha256,
        'upstream_library': provenance.libraryPath,
        'upstream_library_sha256': provenance.librarySha256,
        'platform': 'macos',
        'architecture': 'arm64',
        'minimum_os': provenance.minimumOS,
        'delegates': ['cpu', 'gpu'],
        'bytes': libraryBytes.length,
        'sha256': libraryHash,
        'files': {'libmediapipe.dylib': libraryHash, ...provenance.notices},
        'packaging': {
          'install_name': '@rpath/libmediapipe.dylib',
          'section_layout_unchanged': true,
        },
      }),
    );
  });

  tearDown(() => directory.delete(recursive: true));

  test('accepts pinned official-wheel provenance and notices', () async {
    expect(
      (await validateVisionLibrary(
        directory,
        expectedSha256: libraryHash,
        libraryName: 'libmediapipe.dylib',
        officialWheel: provenance,
      )).path,
      library.path,
    );
  });

  test('rejects an official manifest through the source-build path', () async {
    await expectLater(
      validateVisionLibrary(
        directory,
        expectedSha256: libraryHash,
        libraryName: 'libmediapipe.dylib',
      ),
      throwsStateError,
    );
  });

  test('rejects notice bytes that disagree with the wheel pin', () async {
    await File.fromUri(
      directory.uri.resolve('NOTICE'),
    ).writeAsString('modified');
    await expectLater(
      validateVisionLibrary(
        directory,
        expectedSha256: libraryHash,
        libraryName: 'libmediapipe.dylib',
        officialWheel: provenance,
      ),
      throwsStateError,
    );
  });
}
