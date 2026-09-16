import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_vision/src/native_assets/android_library.dart';
import 'package:test/test.dart';

Uint8List elf(
  String name,
  String abi,
  List<String> needed, {
  int alignment = 16384,
}) {
  final bytes = Uint8List(1024);
  bytes.setAll(0, [0x7f, 0x45, 0x4c, 0x46, 2, 1, 1]);
  final data = ByteData.sublistView(bytes);
  void u16(int offset, int value) =>
      data.setUint16(offset, value, Endian.little);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  void u64(int offset, int value) =>
      data.setUint64(offset, value, Endian.little);
  u16(16, 3);
  u16(18, abi == 'arm64-v8a' ? 183 : 62);
  u64(32, 64);
  u16(54, 56);
  u16(56, 2);
  u32(64, 1);
  u64(96, bytes.length);
  u64(104, bytes.length);
  u64(112, alignment);
  u32(120, 2);
  u64(128, 256);
  final strings = <int>[0];
  int addString(String value) {
    final offset = strings.length;
    strings.addAll([...utf8.encode(value), 0]);
    return offset;
  }

  final soname = addString(name);
  final indices = needed.map(addString).toList();
  final entries = [
    (5, 512),
    (10, strings.length),
    (14, soname),
    for (final index in indices) (1, index),
    (0, 0),
  ];
  u64(152, entries.length * 16);
  for (var i = 0; i < entries.length; i++) {
    u64(256 + i * 16, entries[i].$1);
    u64(264 + i * 16, entries[i].$2);
  }
  bytes.setAll(512, strings);
  return bytes;
}

void main() {
  late Directory directory;
  late Map<String, dynamic> manifest;
  Future<void> saveManifest() => File(
    '${directory.path}/manifest.json',
  ).writeAsString(jsonEncode(manifest));
  Future<void> replaceLibrary(String name, Uint8List bytes) async {
    await File('${directory.path}/$name').writeAsBytes(bytes);
    final hash = sha256.convert(bytes).toString();
    if (name == 'libmediapipe.so') {
      manifest['sha256'] = hash;
      manifest['bytes'] = bytes.length;
    } else {
      manifest['dependencies'][name] = hash;
    }
    await saveManifest();
  }

  Future<List<File>> validate({String abi = 'arm64-v8a', int api = 24}) =>
      validateAndroidVisionLibrary(directory, abi: abi, targetApi: api);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('android-runtime-test-');
    manifest = {
      'platform': 'android',
      'abi': 'arm64-v8a',
      'revision': '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120',
      'ndk_version': '28.2.13676358',
      'minimum_api': 24,
      'validation_delegates': ['cpu'],
      'toolchain_overlay': {
        'opencv_sdk_sha256':
            'fd7f2332331b4eb8b67e55137281cfb16823c9399d90deb9cfa3476783b99e35',
      },
      'dependencies': <String, String>{},
    };
    for (final name in [
      'LICENSE',
      'NOTICE',
      'OPENCV_LICENSE',
      'NDK_NOTICE',
      'opencv-licenses/CAROTENE_NOTICES',
    ]) {
      final file = File('${directory.path}/$name');
      await file.parent.create(recursive: true);
      await file.writeAsString('Fixture notice');
    }
    await replaceLibrary(
      'libmediapipe.so',
      elf('libmediapipe.so', 'arm64-v8a', ['libopencv_java4.so', 'libc.so']),
    );
    await replaceLibrary(
      'libopencv_java4.so',
      elf('libopencv_java4.so', 'arm64-v8a', ['libc++_shared.so', 'libc.so']),
    );
    await replaceLibrary(
      'libc++_shared.so',
      elf('libc++_shared.so', 'arm64-v8a', ['libc.so']),
    );
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'accepts a complete arm64 runtime and its native dependencies',
    () async {
      expect((await validate()).map((file) => file.uri.pathSegments.last), [
        'libmediapipe.so',
        'libopencv_java4.so',
        'libc++_shared.so',
      ]);
    },
  );
  test(
    'accepts x64 only when the manifest and all ELF architectures agree',
    () async {
      manifest['abi'] = 'x86_64';
      for (final name in [
        'libmediapipe.so',
        'libopencv_java4.so',
        'libc++_shared.so',
      ]) {
        await replaceLibrary(name, elf(name, 'x86_64', ['libc.so']));
      }
      expect(await validate(abi: 'x86_64'), hasLength(3));
      await expectLater(validate(), throwsStateError);
    },
  );
  test(
    'rejects modified bytes even when the file still has a valid ELF header',
    () async {
      final file = File('${directory.path}/libopencv_java4.so');
      final bytes = await file.readAsBytes();
      bytes[1023] = 1;
      await file.writeAsBytes(bytes);
      await expectLater(validate(), throwsStateError);
    },
  );
  test(
    'rejects a dependency with the wrong ELF architecture despite matching hashes',
    () async {
      await replaceLibrary(
        'libc++_shared.so',
        elf('libc++_shared.so', 'x86_64', ['libc.so']),
      );
      await expectLater(validate(), throwsStateError);
    },
  );
  test('rejects a 4 KB-only dependency despite matching hashes', () async {
    await replaceLibrary(
      'libopencv_java4.so',
      elf('libopencv_java4.so', 'arm64-v8a', ['libc.so'], alignment: 4096),
    );
    await expectLater(validate(), throwsStateError);
  });
  test(
    'rejects dependencies outside the bundle and Android system libraries',
    () async {
      await replaceLibrary(
        'libmediapipe.so',
        elf('libmediapipe.so', 'arm64-v8a', ['libmissing.so']),
      );
      await expectLater(validate(), throwsStateError);
    },
  );
  test(
    'rejects a SONAME that the loader cannot resolve by the bundled filename',
    () async {
      await replaceLibrary(
        'libopencv_java4.so',
        elf('libdifferent.so', 'arm64-v8a', ['libc.so']),
      );
      await expectLater(validate(), throwsStateError);
    },
  );
  test('rejects an incomplete native dependency set', () async {
    manifest['dependencies'].remove('libc++_shared.so');
    await saveManifest();
    await expectLater(validate(), throwsStateError);
  });
  test('rejects a runtime newer than the app minimum API', () async {
    await expectLater(validate(api: 23), throwsStateError);
  });
  test('rejects missing required dependency notices', () async {
    await File('${directory.path}/NDK_NOTICE').delete();
    await expectLater(validate(), throwsStateError);
  });
}
