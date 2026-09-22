import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/vision_library.dart';
import 'package:test/test.dart';

import 'synthetic_macho.dart';

void main() {
  late Directory directory;
  late File library;
  late OfficialWheelProvenance provenance;
  // A locally re-signed official library pins its unsigned image; the signed
  // file's digest is only recorded, since it depends on the signing Xcode.
  final libraryBytes = syntheticSignedMachO();
  final licenseBytes = utf8.encode('official license');
  final noticeBytes = utf8.encode('official notice');
  final libraryHash = sha256.convert(libraryBytes).toString();
  final unsignedHash = unsignedMachOSha256(libraryBytes);

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
        'unsigned_sha256': unsignedHash,
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
        expectedSha256: unsignedHash,
        libraryName: 'libmediapipe.dylib',
        officialWheel: provenance,
      )).path,
      library.path,
    );
  });

  test('accepts the same image re-signed by a different toolchain', () async {
    // Same header, code and data; a different signature blob and therefore a
    // different whole-file digest, exactly what a newer Xcode produces.
    final resigned = syntheticSignedMachO(signature: [5, 5, 5, 5, 5, 5, 5, 5]);
    await library.writeAsBytes(resigned);
    final manifestFile = File.fromUri(directory.uri.resolve('manifest.json'));
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final resignedHash = sha256.convert(resigned).toString();
    manifest['bytes'] = resigned.length;
    manifest['sha256'] = resignedHash;
    (manifest['files'] as Map<String, dynamic>)['libmediapipe.dylib'] =
        resignedHash;
    await manifestFile.writeAsString(jsonEncode(manifest));
    expect(
      (await validateVisionLibrary(
        directory,
        expectedSha256: unsignedHash,
        libraryName: 'libmediapipe.dylib',
        officialWheel: provenance,
      )).path,
      library.path,
    );
  });

  test('rejects a library whose unsigned image differs from the pin', () async {
    // The manifest is internally consistent, so only the pin catches this.
    final tampered = syntheticSignedMachO(payload: [9, 9, 9, 9]);
    await library.writeAsBytes(tampered);
    final manifestFile = File.fromUri(directory.uri.resolve('manifest.json'));
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final tamperedHash = sha256.convert(tampered).toString();
    manifest['sha256'] = tamperedHash;
    (manifest['files'] as Map<String, dynamic>)['libmediapipe.dylib'] =
        tamperedHash;
    await manifestFile.writeAsString(jsonEncode(manifest));
    await expectLater(
      validateVisionLibrary(
        directory,
        expectedSha256: unsignedHash,
        libraryName: 'libmediapipe.dylib',
        officialWheel: provenance,
      ),
      throwsStateError,
    );
  });

  test('rejects a signed-file digest that disagrees with the file', () async {
    final manifestFile = File.fromUri(directory.uri.resolve('manifest.json'));
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    manifest['sha256'] = '0' * 64;
    await manifestFile.writeAsString(jsonEncode(manifest));
    await expectLater(
      validateVisionLibrary(
        directory,
        expectedSha256: unsignedHash,
        libraryName: 'libmediapipe.dylib',
        officialWheel: provenance,
      ),
      throwsStateError,
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
        expectedSha256: unsignedHash,
        libraryName: 'libmediapipe.dylib',
        officialWheel: provenance,
      ),
      throwsStateError,
    );
  });
}
