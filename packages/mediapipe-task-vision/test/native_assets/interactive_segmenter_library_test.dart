import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/interactive_segmenter_library.dart';
import 'package:test/test.dart';

import '../../sdk_downloads.dart';

void main() {
  late Directory root;
  late Directory cache;
  late List<int> official;
  late List<int> response;
  late HttpServer server;
  late int port;
  late int requests;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('segmenter-download-test-');
    final candidate = File(
      'build/releases/interactive-segmenter-v1.0.1-1/'
      'mediapipe-interactive-segmenter-1.0.1-macos-arm64.tar.gz',
    );
    final archive = await candidate.exists()
        ? candidate
        : await downloadVerified(
            interactiveSegmenterArchive,
            File.fromUri(root.uri.resolve('official.tar.gz')),
          );
    official = await archive.readAsBytes();
    expect(
      sha256.convert(official).toString(),
      interactiveSegmenterArchive.sha256,
    );
  });
  tearDownAll(() => root.delete(recursive: true));
  setUp(() async {
    cache = await root.createTemp('cache-');
    response = official;
    requests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      requests++;
      request.response.add(response);
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await cache.delete(recursive: true);
  });

  Future<File> download({String? checksum}) =>
      downloadInteractiveSegmenterLibrary(
        asset: (
          url: 'http://127.0.0.1:$port/runtime.tar.gz',
          sha256: checksum ?? sha256.convert(response).toString(),
        ),
        cache: cache,
      );

  test(
    'pinned archive installs, works offline and repairs corrupt cache',
    () async {
      final library = await download();
      expect(requests, 1);
      expect(await library.length(), 100946816);
      await server.close(force: true);
      expect((await download()).path, library.path);
      await library.writeAsString('tampered');
      await File.fromUri(
        library.parent.uri.resolve('manifest.json'),
      ).writeAsString('broken JSON');
      await File.fromUri(library.parent.uri.resolve('NOTICE')).delete();
      expect((await download()).path, library.path);
      expect(await library.length(), 100946816);
      expect(requests, 1);
    },
  );

  test(
    'rejects wrong platform, delegate, payload provenance and license',
    () async {
      final library = await download();
      final file = File.fromUri(library.parent.uri.resolve('manifest.json'));
      final original =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final change in <String, Object>{
        'platform': 'ios',
        'minimum_os': '11.0',
        'delegates': ['cpu', 'gpu'],
        'upstream_version': '1.0.0',
        'packaging': {'section_layout_unchanged': false},
      }.entries) {
        await file.writeAsString(
          jsonEncode({...original, change.key: change.value}),
        );
        await expectLater(
          validateInteractiveSegmenterLibrary(library.parent),
          throwsStateError,
        );
      }
      await file.writeAsString(jsonEncode(original));
      await File.fromUri(
        library.parent.uri.resolve('LICENSE'),
      ).writeAsString('changed license');
      await expectLater(
        validateInteractiveSegmenterLibrary(library.parent),
        throwsStateError,
      );
    },
  );

  test('wrong archive checksum never publishes a library', () async {
    await expectLater(download(checksum: '0' * 64), throwsStateError);
    expect(
      await cache
          .list(recursive: true)
          .where((file) => file.path.endsWith('.dylib'))
          .isEmpty,
      isTrue,
    );
  });

  for (final extra in [
    ArchiveFile.string('../outside', 'bad'),
    ArchiveFile.string('/absolute', 'bad'),
    ArchiveFile.string('extra.txt', 'bad'),
    ArchiveFile.symlink(interactiveSegmenterLibraryName, '../../outside'),
  ]) {
    test('rejects unsafe/unexpected entry ${extra.name}', () async {
      response = GZipEncoder().encodeBytes(
        TarEncoder().encodeBytes(Archive()..add(extra)),
      );
      await expectLater(download(), throwsFormatException);
      expect(
        await cache
            .list(recursive: true)
            .where((file) => file.path.endsWith('.dylib'))
            .isEmpty,
        isTrue,
      );
    });
  }

  test('rejects an archive missing upstream notices', () async {
    response = GZipEncoder().encodeBytes(
      TarEncoder().encodeBytes(
        Archive()..add(ArchiveFile.string('manifest.json', '{}')),
      ),
    );
    await expectLater(download(), throwsFormatException);
  });
}
