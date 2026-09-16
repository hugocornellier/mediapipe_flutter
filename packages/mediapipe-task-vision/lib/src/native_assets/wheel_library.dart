import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';

/// A checksum-pinned native C API distributed in Google's official wheel.
final class VisionWheelRelease {
  /// Pins a target, wheel, native member and attribution files.
  const VisionWheelRelease({
    required this.target,
    required this.wheel,
    required this.libraryName,
    required this.librarySha256,
    required this.notices,
    required this.tasks,
  });

  /// Exact build target supported by the binary.
  final String target;

  /// Immutable official wheel URL and checksum.
  final DownloadAsset wheel;

  /// Physical native library filename in the wheel and app bundle.
  final String libraryName;

  /// Independently reviewed checksum of the native library.
  final String librarySha256;

  /// Attribution filenames and their independently pinned checksums.
  final Map<String, String> notices;

  /// Tasks permitted by this release's build hook.
  final Set<String> tasks;

  /// Native C API member in the wheel.
  String get libraryPath => 'mediapipe/tasks/c/$libraryName';

  /// Attribution member in the wheel.
  String noticePath(String name) => 'mediapipe-1.0.0.dist-info/licenses/$name';
}

/// Extracts only the native library and pinned notices; Python is not required.
/// A cached library is reused only after checking every packaged file.
Future<File> downloadVisionWheel(
  VisionWheelRelease release,
  Directory cache,
) async {
  final directory = Directory.fromUri(
    cache.uri.resolve('${release.wheel.sha256}/'),
  );
  final expected = {
    release.libraryName: release.librarySha256,
    ...release.notices,
  };
  final receipt = jsonEncode({
    'runtime': 'mediapipe==1.0.0',
    'source': 'official-wheel',
    'target': release.target,
    'wheel_sha256': release.wheel.sha256,
    'files': expected,
  });
  final manifest = File.fromUri(directory.uri.resolve('manifest.json'));
  var valid =
      await manifest.exists() && await manifest.readAsString() == receipt;
  for (final entry in expected.entries) {
    final file = File.fromUri(directory.uri.resolve(entry.key));
    valid =
        valid &&
        await file.exists() &&
        (await sha256.bind(file.openRead()).first).toString() == entry.value;
  }
  final library = File.fromUri(directory.uri.resolve(release.libraryName));
  if (valid) return library;

  await directory.create(recursive: true);
  final wheel = File.fromUri(directory.uri.resolve('runtime.whl'));
  await downloadVerified(release.wheel, wheel);
  final archive = ZipDecoder().decodeBytes(await wheel.readAsBytes());
  final extracted = <String, List<int>>{};
  final paths = {
    release.libraryPath: release.libraryName,
    for (final name in release.notices.keys) release.noticePath(name): name,
  };
  for (final member in archive) {
    final name = paths[member.name];
    if (name == null) continue;
    if (!member.isFile ||
        member.isSymbolicLink ||
        extracted.containsKey(name)) {
      throw FormatException('Invalid wheel member: ${member.name}');
    }
    final bytes = member.content;
    if (sha256.convert(bytes).toString() != expected[name]) {
      throw StateError('SHA-256 mismatch for wheel member ${member.name}');
    }
    extracted[name] = bytes;
  }
  if (extracted.length != expected.length) {
    throw const FormatException('Official wheel is missing a pinned file.');
  }
  _validateArchitecture(extracted[release.libraryName]!, release.target);
  final temporary = await directory.createTemp('.extract-');
  try {
    for (final entry in extracted.entries) {
      await File.fromUri(
        temporary.uri.resolve(entry.key),
      ).writeAsBytes(entry.value, flush: true);
    }
    await File.fromUri(
      temporary.uri.resolve('manifest.json'),
    ).writeAsString(receipt, flush: true);
    // Publish the library last so failed extraction cannot expose a partial DLL.
    for (final name in [
      ...release.notices.keys,
      'manifest.json',
      release.libraryName,
    ]) {
      await File.fromUri(
        temporary.uri.resolve(name),
      ).rename(File.fromUri(directory.uri.resolve(name)).path);
    }
  } finally {
    await temporary.delete(recursive: true);
  }
  return library;
}

void _validateArchitecture(List<int> bytes, String target) {
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  var valid = false;
  if (target == 'linux/x64' && bytes.length >= 64) {
    valid =
        bytes[0] == 0x7f &&
        bytes[1] == 0x45 &&
        bytes[2] == 0x4c &&
        bytes[3] == 0x46 &&
        bytes[4] == 2 &&
        bytes[5] == 1 &&
        data.getUint16(18, Endian.little) == 62;
  } else if (target == 'windows/x64' &&
      bytes.length >= 64 &&
      bytes[0] == 0x4d &&
      bytes[1] == 0x5a) {
    final offset = data.getUint32(0x3c, Endian.little);
    valid =
        offset + 26 <= bytes.length &&
        data.getUint32(offset, Endian.little) == 0x00004550 &&
        data.getUint16(offset + 4, Endian.little) == 0x8664 &&
        data.getUint16(offset + 24, Endian.little) == 0x20b;
  }
  if (!valid) throw FormatException('Native library does not match $target.');
}
