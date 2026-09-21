import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';

const _mediaPipeRevision = '6d31f1ebc3284db74d211d62bdc4f0a0c29ea120';
const _openCvRevision = '49486f61fb25722cbcf586b7f4320921d46fb38e';

/// SHA-256 of a signed thin arm64 Mach-O with its code signature masked out.
///
/// `codesign` rewrites exactly three things when it re-signs a dylib: the
/// signature blob at the end of `__LINKEDIT`, that segment's `vmsize` and
/// `filesize`, and `LC_CODE_SIGNATURE`'s `dataoff` and `datasize`. Different
/// Xcode releases emit different blobs, so a pin on the signed file breaks
/// with every toolchain update. This digest covers everything before the blob
/// with those fields zeroed: the header including rewritten install names,
/// code, data and fixups, and nothing the signer chooses. It matches
/// `tool/macho_metadata.py`'s `unsigned_sha256`.
String unsignedMachOSha256(Uint8List data) {
  final view = ByteData.sublistView(data);
  if (data.length < 32 || view.getUint32(0, Endian.little) != 0xfeedfacf) {
    throw const FormatException('Expected a thin little-endian Mach-O 64.');
  }
  final image = Uint8List.fromList(data);
  final commands = view.getUint32(16, Endian.little);
  var position = 32;
  var end = data.length;
  for (var i = 0; i < commands; i++) {
    if (position + 8 > data.length) {
      throw const FormatException('Truncated Mach-O load commands.');
    }
    final command = view.getUint32(position, Endian.little);
    final length = view.getUint32(position + 4, Endian.little);
    if (command == 0x19 &&
        position + 56 <= data.length &&
        _segmentName(data, position + 8) == '__LINKEDIT') {
      // vmsize at +32 and filesize at +48; fileoff between them stays.
      image.fillRange(position + 32, position + 40, 0);
      image.fillRange(position + 48, position + 56, 0);
    }
    if (command == 0x1d && position + 16 <= data.length) {
      end = view.getUint32(position + 8, Endian.little);
      image.fillRange(position + 8, position + 16, 0);
    }
    if (length < 8) throw const FormatException('Invalid Mach-O load command.');
    position += length;
  }
  if (end > data.length) {
    throw const FormatException('Mach-O signature offset past end of file.');
  }
  return sha256.convert(Uint8List.sublistView(image, 0, end)).toString();
}

String _segmentName(Uint8List data, int offset) {
  final bytes = data.sublist(offset, offset + 16);
  final terminator = bytes.indexOf(0);
  return ascii.decode(terminator < 0 ? bytes : bytes.sublist(0, terminator));
}

/// Supported native artifact targets. Simulator and device ARM64 are distinct.
enum VisionLibraryTarget {
  /// macOS runtime with CPU and Metal support.
  macosArm64,

  /// iOS simulator runtime with CPU support, built with the simulator SDK.
  iosSimulatorArm64,

  /// iPhone runtime with CPU support, built with the device SDK.
  iosArm64,
}

/// Immutable provenance expected from a runtime extracted from an official
/// MediaPipe Python wheel.
final class OfficialWheelProvenance {
  /// Describes the exact wheel inputs and runtime claims a manifest must match.
  const OfficialWheelProvenance({
    required this.version,
    required this.wheel,
    required this.libraryPath,
    required this.librarySha256,
    required this.minimumOS,
    required this.delegates,
    required this.notices,
  });

  /// Upstream MediaPipe package version.
  final String version;

  /// Immutable wheel URL and digest.
  final DownloadAsset wheel;

  /// Library member path inside the wheel.
  final String libraryPath;

  /// Digest of the library before loader/signing metadata adjustments.
  final String librarySha256;

  /// Minimum operating-system version encoded in the library.
  final String minimumOS;

  /// Delegates validated for this prepared runtime.
  final Set<String> delegates;

  /// Upstream notice filenames and their wheel-content digests.
  final Map<String, String> notices;
}

/// The validation target for a hook build target string; see `buildTarget`.
VisionLibraryTarget visionLibraryTarget(String target) => switch (target) {
  'macos/arm64' => VisionLibraryTarget.macosArm64,
  'ios-simulator/arm64' => VisionLibraryTarget.iosSimulatorArm64,
  'ios/arm64' => VisionLibraryTarget.iosArm64,
  _ => throw UnsupportedError(
    'mediapipe_flutter_vision has no native runtime validation for $target.',
  ),
};

Set<String> _requiredFiles(
  String libraryName,
  OfficialWheelProvenance? officialWheel,
) => {
  libraryName,
  'manifest.json',
  'LICENSE',
  'NOTICE',
  if (officialWheel == null) ...{
    'opencv-licenses/LICENSE',
    'opencv-licenses/CAROTENE_NOTICES',
  },
};

/// Checks both provenance and the library bytes before loading native code.
/// Source builds use their manifest digest; downloads also require a pinned
/// digest independent of the downloaded manifest.
Future<File> validateVisionLibrary(
  Directory directory, {
  String? expectedSha256,
  String libraryName = 'libface_detector.dylib',
  VisionLibraryTarget target = VisionLibraryTarget.macosArm64,
  OfficialWheelProvenance? officialWheel,
}) async {
  _checkLibraryName(libraryName);
  final library = File.fromUri(directory.uri.resolve(libraryName));
  final manifestFile = File.fromUri(directory.uri.resolve('manifest.json'));
  final manifest = jsonDecode(await manifestFile.readAsString());
  final simulator = target == VisionLibraryTarget.iosSimulatorArm64;
  final device = target == VisionLibraryTarget.iosArm64;
  final expectedSdk = simulator
      ? 'iphonesimulator'
      : device
      ? 'iphoneos'
      : null;
  // A source-built or downloaded archive pins the whole file. A locally
  // re-signed official wheel pins the unsigned image instead, since its signed
  // bytes depend on the Xcode that signed it; the whole-file digest is still
  // checked against the manifest so a damaged cache is never loaded.
  final pinsSignedFile = officialWheel == null;
  if (manifest is! Map<String, dynamic> ||
      manifest['platform'] != (simulator || device ? 'ios' : 'macos') ||
      manifest['architecture'] != 'arm64' ||
      manifest['ios_sdk'] != expectedSdk ||
      manifest['bytes'] != await library.length() ||
      (pinsSignedFile &&
          expectedSha256 != null &&
          manifest['sha256'] != expectedSha256) ||
      (await sha256.bind(library.openRead()).first).toString() !=
          manifest['sha256']) {
    throw StateError('MediaPipe native artifact provenance/hash mismatch.');
  }
  final delegates = manifest['delegates'];
  if (officialWheel == null) {
    if (manifest['revision'] != _mediaPipeRevision ||
        manifest['opencv_revision'] != _openCvRevision) {
      throw StateError('MediaPipe native artifact provenance/hash mismatch.');
    }
  } else {
    final packaging = manifest['packaging'];
    final files = manifest['files'];
    if (simulator ||
        device ||
        expectedSha256 == null ||
        manifest['origin'] != 'official-pypi-wheel' ||
        manifest['upstream_version'] != officialWheel.version ||
        manifest['upstream_url'] != officialWheel.wheel.url ||
        manifest['upstream_sha256'] != officialWheel.wheel.sha256 ||
        manifest['upstream_library'] != officialWheel.libraryPath ||
        manifest['upstream_library_sha256'] != officialWheel.librarySha256 ||
        manifest['minimum_os'] != officialWheel.minimumOS ||
        packaging is! Map<String, dynamic> ||
        packaging['install_name'] != '@rpath/libmediapipe.dylib' ||
        packaging['section_layout_unchanged'] != true ||
        files is! Map<String, dynamic> ||
        files[libraryName] != manifest['sha256'] ||
        manifest['unsigned_sha256'] != expectedSha256 ||
        officialWheel.notices.entries.any(
          (notice) => files[notice.key] != notice.value,
        )) {
      throw StateError('Official MediaPipe wheel provenance/hash mismatch.');
    }
    final String unsigned;
    try {
      unsigned = unsignedMachOSha256(await library.readAsBytes());
    } on FormatException {
      throw StateError('Official MediaPipe library is not a signed Mach-O.');
    }
    if (unsigned != expectedSha256) {
      throw StateError(
        'Official MediaPipe library unsigned-image hash mismatch.',
      );
    }
    for (final notice in officialWheel.notices.entries) {
      final file = File.fromUri(directory.uri.resolve(notice.key));
      if (!await file.exists() ||
          (await sha256.bind(file.openRead()).first).toString() !=
              notice.value) {
        throw StateError('Official MediaPipe notice hash mismatch.');
      }
    }
  }
  // Metal is expected on macOS. Neither iOS slice ships a GPU delegate, so
  // both require CPU alone rather than being held to the desktop rule.
  final requiredDelegates =
      officialWheel?.delegates ??
      (simulator || device ? const {'cpu'} : const {'cpu', 'gpu'});
  if (delegates is! List || !requiredDelegates.every(delegates.contains)) {
    throw StateError(
      simulator
          ? 'The iOS simulator requires a CPU runtime. '
                'Build it with tool/build_ios_simulator.py.'
          : device
          ? 'The iOS device runtime requires a CPU runtime. '
                'Build it with tool/build_ios_simulator.py --device.'
          : 'This package requires a CPU and Metal runtime. Rebuild the local '
                'native library without --cpu-only, or use prebuilt: true.',
    );
  }
  return library;
}

/// Downloads and unpacks a pinned runtime using Dart, with no native compiler,
/// shell archive utility, or GitHub credentials required.
Future<File> downloadVisionLibrary({
  required DownloadAsset asset,
  required String librarySha256,
  required Directory cache,
  String libraryName = 'libface_detector.dylib',
  VisionLibraryTarget target = VisionLibraryTarget.macosArm64,
  OfficialWheelProvenance? officialWheel,
}) async {
  _checkLibraryName(libraryName);
  final requiredFiles = _requiredFiles(libraryName, officialWheel);
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(asset.sha256) ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(librarySha256)) {
    throw ArgumentError('Expected SHA-256 hex digests for the native runtime.');
  }
  final directory = Directory.fromUri(cache.uri.resolve('${asset.sha256}/'));
  final archiveFile = File.fromUri(directory.uri.resolve('runtime.tar.gz'));
  // Validate the compressed cache too, repairing it through downloadVerified.
  await downloadVerified(asset, archiveFile);
  try {
    final library = await validateVisionLibrary(
      directory,
      expectedSha256: librarySha256,
      libraryName: libraryName,
      target: target,
      officialWheel: officialWheel,
    );
    if (await Future.wait([
      for (final name in requiredFiles)
        File.fromUri(directory.uri.resolve(name)).exists(),
    ]).then((exists) => exists.every((value) => value))) {
      return library;
    }
  } on FileSystemException {
    // Missing or interrupted extraction; recover from the verified archive.
  } on FormatException {
    // A damaged cached manifest can be recovered the same way.
  } on StateError {
    // Never load modified cache contents; replace them from the pinned archive.
  }

  final temporary = await directory.createTemp('.unpack-');
  try {
    final seen = <String>{};
    final archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(await archiveFile.readAsBytes()),
      callback: (entry) {
        final name = entry.name;
        final parts = name.split('/');
        final license =
            parts.length == 2 &&
            parts.first == 'opencv-licenses' &&
            RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(parts.last) &&
            parts.last != '.' &&
            parts.last != '..';
        if (!entry.isFile ||
            entry.isSymbolicLink ||
            !seen.add(name) ||
            !(requiredFiles.contains(name) ||
                (officialWheel == null && license))) {
          throw FormatException('Unexpected native archive entry: $name');
        }
      },
    );
    if (!seen.containsAll(requiredFiles)) {
      throw const FormatException('Native archive is missing required files.');
    }
    // We write only individually validated file names and never follow archive
    // links or ask a general-purpose extractor to choose destination paths.
    for (final entry in archive) {
      final file = File.fromUri(temporary.uri.resolve(entry.name));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.readBytes()!);
    }
    await validateVisionLibrary(
      temporary,
      expectedSha256: librarySha256,
      libraryName: libraryName,
      target: target,
      officialWheel: officialWheel,
    );
    // Publish the library last. Each rename is atomic and concurrent hooks
    // write identical content within this digest-specific cache directory.
    for (final entry in archive.where((entry) => entry.name != libraryName)) {
      final destination = File.fromUri(directory.uri.resolve(entry.name));
      await destination.parent.create(recursive: true);
      await File.fromUri(
        temporary.uri.resolve(entry.name),
      ).rename(destination.path);
    }
    return await File.fromUri(
      temporary.uri.resolve(libraryName),
    ).rename(File.fromUri(directory.uri.resolve(libraryName)).path);
  } finally {
    await temporary.delete(recursive: true);
  }
}

/// Names a vision runtime may have. This is a closed set so a release row can
/// never name an arbitrary path inside an extracted archive.
const _libraryNames = {
  'libface_detector.dylib',
  'libface_landmarker.dylib',
  // The combined source build covering every open-source task.
  'libmediapipe.dylib',
};

void _checkLibraryName(String name) {
  if (!_libraryNames.contains(name)) {
    throw ArgumentError.value(
      name,
      'libraryName',
      'Unsupported vision runtime',
    );
  }
}
