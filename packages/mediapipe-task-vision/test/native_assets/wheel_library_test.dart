import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/wheel_library.dart';
import 'package:test/test.dart';

void main() {
  for (final target in ['linux/x64', 'windows/x64']) {
    group(target, () {
      late Directory cache;
      late HttpServer server;
      late Uint8List library;
      late List<int> response;
      late VisionWheelRelease release;
      var requests = 0;
      final name = target.startsWith('linux')
          ? 'libmediapipe.so'
          : 'libmediapipe.dll';
      const notices = {'LICENSE': 'license', 'NOTICE': 'notice'};

      List<int> bundle({bool missingNotice = false, List<int>? contents}) {
        final archive = Archive()
          ..add(
            ArchiveFile.bytes('mediapipe/tasks/c/$name', contents ?? library),
          )
          ..add(
            ArchiveFile.string('../unrelated-python-file', 'never extract'),
          );
        for (final entry in notices.entries) {
          if (missingNotice && entry.key == 'NOTICE') continue;
          archive.add(
            ArchiveFile.string(
              'mediapipe-1.0.0.dist-info/licenses/${entry.key}',
              entry.value,
            ),
          );
        }
        return ZipEncoder().encodeBytes(archive);
      }

      void pin({String? wheelHash, String? libraryHash}) {
        release = VisionWheelRelease(
          target: target,
          wheel: (
            url: 'http://127.0.0.1:${server.port}/runtime.whl',
            sha256: wheelHash ?? sha256.convert(response).toString(),
          ),
          libraryName: name,
          librarySha256: libraryHash ?? sha256.convert(library).toString(),
          notices: {
            for (final entry in notices.entries)
              entry.key: sha256.convert(utf8.encode(entry.value)).toString(),
          },
          tasks: {'face_detector'},
        );
      }

      setUp(() async {
        cache = await Directory.systemTemp.createTemp('vision-wheel-');
        library = Uint8List(128);
        final data = ByteData.sublistView(library);
        if (target.startsWith('linux')) {
          library.setAll(0, [0x7f, 0x45, 0x4c, 0x46, 2, 1]);
          data.setUint16(18, 62, Endian.little);
        } else {
          library.setAll(0, [0x4d, 0x5a]);
          data.setUint32(0x3c, 64, Endian.little);
          data.setUint32(64, 0x4550, Endian.little);
          data.setUint16(68, 0x8664, Endian.little);
          data.setUint16(88, 0x20b, Endian.little);
        }
        requests = 0;
        response = bundle();
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          requests++;
          request.response.add(response);
          await request.response.close();
        });
        pin();
      });
      tearDown(() async {
        await server.close(force: true);
        await cache.delete(recursive: true);
      });

      test(
        'cold extraction preserves notices and ignores Python paths',
        () async {
          final file = await downloadVisionWheel(release, cache);
          expect(await file.readAsBytes(), library);
          expect(
            await File.fromUri(
              file.parent.uri.resolve('NOTICE'),
            ).readAsString(),
            'notice',
          );
          expect(requests, 1);
          expect(
            await File.fromUri(
              cache.uri.resolve('unrelated-python-file'),
            ).exists(),
            isFalse,
          );
        },
      );
      test(
        'offline cache validates all files and repairs corrupt notices',
        () async {
          final file = await downloadVisionWheel(release, cache);
          await File.fromUri(
            file.parent.uri.resolve('NOTICE'),
          ).writeAsString('corrupt');
          await downloadVisionWheel(release, cache);
          expect(requests, 1); // The checksum-pinned wheel is also cached.
          expect(
            await File.fromUri(
              file.parent.uri.resolve('NOTICE'),
            ).readAsString(),
            'notice',
          );
          await server.close(force: true);
          expect((await downloadVisionWheel(release, cache)).path, file.path);
        },
      );
      test(
        'rejects wheel digest mismatch before publishing a library',
        () async {
          pin(wheelHash: '0' * 64);
          await expectLater(
            downloadVisionWheel(release, cache),
            throwsStateError,
          );
          expect(
            await cache
                .list(recursive: true)
                .any((file) => file.path.endsWith(name)),
            isFalse,
          );
        },
      );
      test('rejects modified native bytes and missing notices', () async {
        response = bundle(contents: [1, 2, 3]);
        pin();
        await expectLater(
          downloadVisionWheel(release, cache),
          throwsStateError,
        );
        response = bundle(missingNotice: true);
        pin();
        await expectLater(
          downloadVisionWheel(release, cache),
          throwsFormatException,
        );
      });
      test(
        'rejects checksum-valid binaries for a different architecture',
        () async {
          library.fillRange(0, library.length, 0);
          response = bundle();
          pin();
          await expectLater(
            downloadVisionWheel(release, cache),
            throwsFormatException,
          );
        },
      );
    });
  }
}
