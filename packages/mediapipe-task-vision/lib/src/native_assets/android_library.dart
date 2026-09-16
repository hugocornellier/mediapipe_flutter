import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _revision = '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120';
const _ndk = '28.2.13676358';
const _opencv =
    'fd7f2332331b4eb8b67e55137281cfb16823c9399d90deb9cfa3476783b99e35';
const _dependencies = {'libopencv_java4.so', 'libc++_shared.so'};
const _systemLibraries = {
  'libc.so',
  'libm.so',
  'libdl.so',
  'liblog.so',
  'libz.so',
  'libandroid.so',
  'libjnigraphics.so',
  'libmediandk.so',
  'libEGL.so',
  'libGLESv2.so',
  'libGLESv3.so',
  'libOpenSLES.so',
};

/// Validate a maintainer Android build and its complete native dependency set.
/// No Android download or physical-device validation is implied by this path.
Future<List<File>> validateAndroidVisionLibrary(
  Directory directory, {
  required String abi,
  required int targetApi,
}) async {
  final manifest = jsonDecode(
    await File.fromUri(directory.uri.resolve('manifest.json')).readAsString(),
  );
  if (!{'arm64-v8a', 'x86_64'}.contains(abi) ||
      manifest is! Map<String, dynamic> ||
      manifest['platform'] != 'android' ||
      manifest['abi'] != abi ||
      manifest['revision'] != _revision ||
      manifest['ndk_version'] != _ndk ||
      manifest['toolchain_overlay'] is! Map ||
      manifest['toolchain_overlay']['opencv_sdk_sha256'] != _opencv ||
      manifest['minimum_api'] is! int ||
      manifest['minimum_api'] < 24 ||
      manifest['minimum_api'] > targetApi ||
      manifest['validation_delegates'] is! List ||
      !manifest['validation_delegates'].contains('cpu')) {
    throw StateError('Android runtime provenance/ABI/API mismatch.');
  }
  final dependencies = manifest['dependencies'];
  if (dependencies is! Map ||
      dependencies.length != _dependencies.length ||
      !dependencies.keys.toSet().containsAll(_dependencies)) {
    throw StateError(
      'Android runtime requires OpenCV and libc++ dependencies.',
    );
  }
  for (final name in {
    'LICENSE',
    'NOTICE',
    'OPENCV_LICENSE',
    'NDK_NOTICE',
    'opencv-licenses/CAROTENE_NOTICES',
  }) {
    final uri = directory.uri.resolve(name);
    if (await Link.fromUri(uri).exists() ||
        !await File.fromUri(uri).exists() ||
        await File.fromUri(uri).length() == 0) {
      throw StateError('Missing Android runtime notice: $name');
    }
  }
  final hashes = {'libmediapipe.so': manifest['sha256'], ...dependencies};
  final libraries = <File>[];
  for (final entry in hashes.entries) {
    final uri = directory.uri.resolve(entry.key as String);
    final file = File.fromUri(uri);
    if (entry.value is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.value) ||
        await Link.fromUri(uri).exists()) {
      throw StateError('Invalid Android runtime hash/file: ${entry.key}');
    }
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != entry.value ||
        (entry.key == 'libmediapipe.so' && manifest['bytes'] != bytes.length)) {
      throw StateError('Android runtime hash mismatch: ${entry.key}');
    }
    final (soname, needed) = _inspectElf(bytes, abi);
    if (soname != entry.key ||
        needed.any(
          (name) =>
              !_systemLibraries.contains(name) && !hashes.containsKey(name),
        )) {
      throw StateError(
        'Android runtime SONAME/dependency mismatch: ${entry.key}',
      );
    }
    libraries.add(file);
  }
  return libraries;
}

(String, Set<String>) _inspectElf(Uint8List bytes, String abi) {
  Never invalid() =>
      throw StateError('Invalid Android ELF architecture/layout.');
  if (bytes.length < 64 ||
      bytes[0] != 0x7f ||
      bytes[1] != 0x45 ||
      bytes[2] != 0x4c ||
      bytes[3] != 0x46 ||
      bytes[4] != 2 ||
      bytes[5] != 1) {
    invalid();
  }
  final data = ByteData.sublistView(bytes);
  int u16(int offset) => data.getUint16(offset, Endian.little);
  int u32(int offset) => data.getUint32(offset, Endian.little);
  int u64(int offset) => data.getUint64(offset, Endian.little);
  if (u16(16) != 3 || u16(18) != (abi == 'arm64-v8a' ? 183 : 62)) invalid();
  final header = u64(32);
  final stride = u16(54);
  final count = u16(56);
  if (stride < 56 || count == 0 || header + stride * count > bytes.length) {
    invalid();
  }
  final loads = <(int, int, int)>[];
  (int, int)? dynamic;
  for (var index = 0; index < count; index++) {
    final offset = header + index * stride;
    final fileOffset = u64(offset + 8);
    final address = u64(offset + 16);
    final size = u64(offset + 32);
    if (fileOffset + size > bytes.length) invalid();
    if (u32(offset) == 1) {
      final alignment = u64(offset + 48);
      if (alignment < 16384 || (address - fileOffset) % 16384 != 0) {
        throw StateError('Android ELF requires 16 KB LOAD alignment.');
      }
      loads.add((fileOffset, address, size));
    } else if (u32(offset) == 2) {
      dynamic = (fileOffset, size);
    }
  }
  if (loads.isEmpty || dynamic == null) invalid();
  var stringAddress = 0;
  var stringSize = 0;
  int? sonameIndex;
  final neededIndices = <int>[];
  final (start, size) = dynamic;
  for (var offset = start; offset + 16 <= start + size; offset += 16) {
    final tag = u64(offset);
    final value = u64(offset + 8);
    if (tag == 0) break;
    if (tag == 1) neededIndices.add(value);
    if (tag == 5) stringAddress = value;
    if (tag == 10) stringSize = value;
    if (tag == 14) sonameIndex = value;
  }
  int? strings;
  for (final (fileOffset, address, size) in loads) {
    if (stringAddress >= address &&
        stringAddress + stringSize <= address + size) {
      strings = fileOffset + stringAddress - address;
    }
  }
  if (strings == null || stringSize == 0 || sonameIndex == null) invalid();
  String stringAt(int index) {
    if (index >= stringSize) invalid();
    final start = strings! + index;
    final end = bytes.indexOf(0, start);
    if (end < start || end >= strings + stringSize) invalid();
    return utf8.decode(bytes.sublist(start, end));
  }

  return (stringAt(sonameIndex), neededIndices.map(stringAt).toSet());
}
