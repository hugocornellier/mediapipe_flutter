import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/vision_library.dart';
import 'package:test/test.dart';

void main() {
  for (final libraryName in [
    'libface_detector.dylib',
    'libface_landmarker.dylib',
    'libmediapipe.dylib',
  ]) {
    group(libraryName, () => _testLibrary(libraryName));
  }
}

void _testLibrary(String libraryName) {
  final libraryBytes = utf8.encode('test native library');
  final libraryHash = sha256.convert(libraryBytes).toString();
  late Directory cache;
  late HttpServer server;
  late int port;
  late List<int> response;
  late int requests;
  var status = 200;

  List<int> bundle({
    String architecture = 'arm64',
    ArchiveFile? extra,
    bool includeNotices = true,
    List<String>? delegates = const ['cpu', 'gpu'],
    String platform = 'macos',
    String? iosSdk,
  }) {
    final archive = Archive()
      ..add(ArchiveFile.bytes(libraryName, libraryBytes))
      ..add(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'revision': '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120',
            'opencv_revision': '49486f61fb25722cbcf586b7f4320921d46fb38e',
            'platform': platform,
            'ios_sdk': ?iosSdk,
            'architecture': architecture,
            'bytes': libraryBytes.length,
            'sha256': libraryHash,
            'delegates': ?delegates,
          }),
        ),
      )
      ..add(ArchiveFile.string('LICENSE', 'license'))
      ..add(ArchiveFile.string('opencv-licenses/LICENSE', 'license'))
      ..add(ArchiveFile.string('opencv-licenses/CAROTENE_NOTICES', 'license'));
    if (includeNotices) archive.add(ArchiveFile.string('NOTICE', 'notices'));
    if (extra != null) archive.add(extra);
    return GZipEncoder().encodeBytes(TarEncoder().encodeBytes(archive));
  }

  Future<File> download({
    String? expectedHash,
    VisionLibraryTarget target = VisionLibraryTarget.macosArm64,
  }) => downloadVisionLibrary(
    asset: (
      url: 'http://127.0.0.1:$port/runtime.tar.gz',
      sha256: expectedHash ?? sha256.convert(response).toString(),
    ),
    librarySha256: libraryHash,
    cache: cache,
    libraryName: libraryName,
    target: target,
  );

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('mediapipe-native-cache-');
    response = bundle();
    requests = 0;
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      requests++;
      request.response.statusCode = status;
      request.response.add(response);
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await cache.delete(recursive: true);
  });

  test('cold install downloads the runtime and preserves notices', () async {
    final library = await download();
    expect(await library.readAsBytes(), libraryBytes);
    expect(requests, 1);
    expect(
      await File.fromUri(library.parent.uri.resolve('NOTICE')).readAsString(),
      'notices',
    );
    expect(
      await File.fromUri(
        library.parent.uri.resolve('opencv-licenses/LICENSE'),
      ).exists(),
      isTrue,
    );
    expect(
      await library.parent.list().any((file) => file.path.contains('.unpack-')),
      isFalse,
    );
  });

  test('warm cache works with the server offline', () async {
    final library = await download();
    await server.close(force: true);
    expect((await download()).path, library.path);
    expect(requests, 1);
  });

  test(
    'downloads simulator CPU archives and validates the offline cache',
    () async {
      response = bundle(
        platform: 'ios',
        iosSdk: 'iphonesimulator',
        delegates: ['cpu'],
      );
      final library = await download(
        target: VisionLibraryTarget.iosSimulatorArm64,
      );
      expect(await library.readAsBytes(), libraryBytes);
      await server.close(force: true);
      expect(
        (await download(target: VisionLibraryTarget.iosSimulatorArm64)).path,
        library.path,
      );
      expect(requests, 1);
      await library.writeAsString('tampered');
      expect(
        await (await download(
          target: VisionLibraryTarget.iosSimulatorArm64,
        )).readAsBytes(),
        libraryBytes,
      );
    },
  );

  test('rejects a device archive selected for a simulator download', () async {
    response = bundle(platform: 'ios', iosSdk: 'iphoneos', delegates: ['cpu']);
    await expectLater(
      download(target: VisionLibraryTarget.iosSimulatorArm64),
      throwsStateError,
    );
  });

  test(
    'simulator CPU artifacts cannot substitute for macOS artifacts',
    () async {
      final library = await download();
      await expectLater(
        validateVisionLibrary(
          library.parent,
          libraryName: libraryName,
          target: VisionLibraryTarget.iosSimulatorArm64,
        ),
        throwsStateError,
      );
      final file = File.fromUri(library.parent.uri.resolve('manifest.json'));
      final manifest =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      manifest.addAll({
        'platform': 'ios',
        'ios_sdk': 'iphonesimulator',
        'delegates': ['cpu'],
      });
      await file.writeAsString(jsonEncode(manifest));
      expect(
        (await validateVisionLibrary(
          library.parent,
          libraryName: libraryName,
          target: VisionLibraryTarget.iosSimulatorArm64,
        )).path,
        library.path,
      );
      await expectLater(
        validateVisionLibrary(library.parent, libraryName: libraryName),
        throwsStateError,
      );
      for (final sdk in ['iphoneos', null]) {
        manifest['ios_sdk'] = sdk;
        await file.writeAsString(jsonEncode(manifest));
        await expectLater(
          validateVisionLibrary(
            library.parent,
            libraryName: libraryName,
            target: VisionLibraryTarget.iosSimulatorArm64,
          ),
          throwsStateError,
        );
      }
    },
  );

  test(
    'simulator artifacts require CPU support and valid library bytes',
    () async {
      final library = await download();
      final file = File.fromUri(library.parent.uri.resolve('manifest.json'));
      final manifest =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      manifest.addAll({
        'platform': 'ios',
        'ios_sdk': 'iphonesimulator',
        'delegates': ['gpu'],
      });
      await file.writeAsString(jsonEncode(manifest));
      await expectLater(
        validateVisionLibrary(
          library.parent,
          libraryName: libraryName,
          target: VisionLibraryTarget.iosSimulatorArm64,
        ),
        throwsStateError,
      );
      manifest['delegates'] = ['cpu'];
      await file.writeAsString(jsonEncode(manifest));
      await library.writeAsString('tampered simulator library');
      await expectLater(
        validateVisionLibrary(
          library.parent,
          libraryName: libraryName,
          target: VisionLibraryTarget.iosSimulatorArm64,
        ),
        throwsStateError,
      );
    },
  );

  test('repairs modified library and manifest using cached archive', () async {
    final library = await download();
    await library.writeAsString('tampered');
    await File.fromUri(
      library.parent.uri.resolve('manifest.json'),
    ).writeAsString('bad JSON');
    await server.close(force: true);
    expect(await (await download()).readAsBytes(), libraryBytes);
    expect(requests, 1);
  });

  test('redownloads a corrupted compressed cache', () async {
    final library = await download();
    await File.fromUri(
      library.parent.uri.resolve('runtime.tar.gz'),
    ).writeAsString('tampered');
    expect(await (await download()).readAsBytes(), libraryBytes);
    expect(requests, 2);
  });

  test('concurrent downloads publish the same complete library', () async {
    final libraries = await Future.wait(List.generate(3, (_) => download()));
    expect(libraries.map((file) => file.path).toSet(), hasLength(1));
    for (final library in libraries) {
      expect(await library.readAsBytes(), libraryBytes);
    }
  });

  test('rejects incorrect archive checksum before unpacking', () async {
    await expectLater(download(expectedHash: '0' * 64), throwsStateError);
    expect(
      await cache
          .list(recursive: true)
          .where((file) => file.path.endsWith('.dylib'))
          .isEmpty,
      isTrue,
    );
  });

  test('HTTP errors leave no usable runtime', () async {
    status = 404;
    await expectLater(download(), throwsA(isA<HttpException>()));
    expect(
      await cache.list(recursive: true).where((entry) => entry is File).isEmpty,
      isTrue,
    );
  });

  test('rejects a manifest for the wrong architecture', () async {
    response = bundle(architecture: 'x64');
    await expectLater(download(), throwsStateError);
    expect(
      await cache
          .list(recursive: true)
          .where((file) => file.path.endsWith('.dylib'))
          .isEmpty,
      isTrue,
    );
  });

  test('rejects incomplete license contents', () async {
    response = bundle(includeNotices: false);
    await expectLater(download(), throwsFormatException);
  });

  for (final delegates in [
    null,
    <String>['cpu'],
    <String>['gpu'],
  ]) {
    test('rejects a runtime without both delegates: $delegates', () async {
      response = bundle(delegates: delegates);
      await expectLater(
        download(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'diagnostic',
            contains('CPU and Metal'),
          ),
        ),
      );
    });
  }

  for (final name in [
    '../outside',
    '/absolute',
    'opencv-licenses/../../outside',
  ]) {
    test('rejects unsafe archive path $name', () async {
      response = bundle(extra: ArchiveFile.string(name, 'unsafe'));
      await expectLater(download(), throwsFormatException);
    });
  }
  test('rejects archive symlinks', () async {
    response = bundle(
      extra: ArchiveFile.symlink('opencv-licenses/link', '../../outside'),
    );
    await expectLater(download(), throwsFormatException);
  });
}
