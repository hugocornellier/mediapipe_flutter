import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import '../../native_assets.dart';

/// The name core's build hook registers Google's MediaPipe engine under; every
/// task family binds it as `package:mediapipe_core/mediapipe.dylib`.
///
/// Core bundles it once per app (Google's official library on desktop, an
/// adapter over Google's SDK on iOS), so vision, text and audio never load a
/// second copy: two copies register MediaPipe's graphs twice and abort. The
/// identifier is stable across platforms and versions; the bundled file name
/// comes from each release.
const tasksRuntimeAssetName = 'mediapipe.dylib';

/// Loader-metadata adjustments recorded by the packaging tool. Code and data
/// bytes are verified unchanged; only load commands and signing differ.
typedef TasksRuntimePackaging = ({
  String unchangedPayloadSha256,
  bool sectionLayoutUnchanged,
});

/// A pinned, immutable runtime release for one build target.
///
/// Every field is compared against the archive's `manifest.json` and file
/// digests before a library is bundled. Supporting another platform means
/// adding a row to [tasksRuntimeReleases] and publishing its archive; the
/// build hook needs no changes.
final class TasksRuntimeRelease {
  /// Describe a published release. All digests are SHA-256 hex.
  const TasksRuntimeRelease({
    required this.target,
    required this.release,
    required this.version,
    required this.archive,
    required this.libraryName,
    required this.librarySha256,
    required this.bytes,
    required this.minimumOs,
    required this.delegates,
    required this.wheelSha256,
    required this.upstreamLibrary,
    required this.upstreamLibrarySha256,
    required this.notices,
    this.packaging,
  });

  /// Build target such as `macos/arm64`; see `buildTarget`.
  final String target;

  /// Release tag in the public native runtime repository.
  final String release;

  /// Google's MediaPipe version the library was taken from, e.g. `1.0.0`.
  final String version;

  /// The archive holding the library, its notices and `manifest.json`.
  final DownloadAsset archive;

  /// Bundle filename of the prepared library.
  final String libraryName;

  /// SHA-256 of the prepared library, before Flutter's final bundling/signing.
  final String librarySha256;

  /// Exact library size, checked before and after extraction.
  final int bytes;

  /// Minimum operating system version recorded by the packaging tool.
  final String minimumOs;

  /// Delegates validated for this release, for example `['cpu']`.
  final List<String> delegates;

  /// SHA-256 of Google's official wheel the library was taken from.
  final String wheelSha256;

  /// Path of the library inside that wheel.
  final String upstreamLibrary;

  /// SHA-256 of the unmodified upstream library.
  final String upstreamLibrarySha256;

  /// License and notice files shipped in the archive, with their digests.
  final Map<String, String> notices;

  /// Expected loader-metadata packaging record, or null when the platform's
  /// library is shipped byte-for-byte as extracted from the wheel.
  final TasksRuntimePackaging? packaging;

  /// Every file the archive must contain, with its digest.
  Map<String, String> get files => {...notices, libraryName: librarySha256};

  /// The platform half of [target].
  String get platform => target.split('/').first;

  /// The architecture half of [target].
  String get architecture => target.split('/').last;

  /// The same release served from another location, for loopback tests.
  TasksRuntimeRelease withArchive(DownloadAsset archive) => TasksRuntimeRelease(
    target: target,
    release: release,
    version: version,
    archive: archive,
    libraryName: libraryName,
    librarySha256: librarySha256,
    bytes: bytes,
    minimumOs: minimumOs,
    delegates: delegates,
    wheelSha256: wheelSha256,
    upstreamLibrary: upstreamLibrary,
    upstreamLibrarySha256: upstreamLibrarySha256,
    notices: notices,
    packaging: packaging,
  );
}

/// Google's official macOS library, repackaged per build target.
///
/// Each row is immutable: a rebuild gets a new release tag and new digests.
/// macOS runs Google's 1.0.0 library: the vision tasks are validated against
/// it, and 1.0.1's detector graphs abort opening a CPU graph on some Macs
/// (upstream-issues.md UP-007). Text, audio and the stateful Interactive
/// Segmenter run on the same image, so an app loads one MediaPipe.
const tasksRuntimeReleases = <String, TasksRuntimeRelease>{
  'macos/arm64': TasksRuntimeRelease(
    target: 'macos/arm64',
    release: 'macos-tasks-runtime-v1.0.0',
    version: '1.0.0',
    archive: DownloadAsset(
      url:
          'https://github.com/hugocornellier/mediapipe_flutter_native/releases/'
          'download/macos-tasks-runtime-v1.0.0/'
          'mediapipe-tasks-runtime-1.0.0-macos-arm64.tar.gz',
      sha256:
          '5a810390e75ccb38d16aaf42c820534becedfa39cc0ef185efc0e8379e9e6d4a',
    ),
    libraryName: 'libmediapipe.dylib',
    librarySha256:
        '06b71d3f0a90180e6ae9e24872a473f5e5b8a97ec9d970555d975c41b5fb8a38',
    bytes: 99219248,
    minimumOs: '14.0',
    delegates: ['cpu', 'gpu'],
    wheelSha256:
        '7ee4783be41b2de345e1eb71e2f7e7c159a50ed5c283e60ccb8f5a6027c70a82',
    upstreamLibrary: 'mediapipe/tasks/c/libmediapipe.dylib',
    upstreamLibrarySha256:
        'aa1314b6cc3eb2ce3b610808433930c016e19cdc0f62cbb3f10cc7e912b6f72f',
    notices: {
      'LICENSE':
          '8707eef0533987efc5b155d64761eeb6e20793f50b9bd1a68dad1cf4719d0ed8',
      'NOTICE':
          'd3b4a80a24a01fd445d4b70a610fd836ec3547c3a62eb835a1041956c38d9f56',
    },
    packaging: (
      unchangedPayloadSha256:
          '21c7861e9a190cdc2af40e4be3b0379d1de6af0dd17c3f5e9065e700a8de1c71',
      sectionLayoutUnchanged: true,
    ),
  ),
};

/// Google's desktop C API libraries, bundled unmodified from the official
/// wheels, which export the text and audio tasks beside the vision ones.
///
/// Every family binds this one copy: two copies of Google's library in one
/// process register its graphs twice and abort. Windows stays on the 1.0.0
/// wheel the vision tasks were validated on; its text and audio C API and
/// Python declarations are the same as 1.0.1's.
const tasksWheelRuntimes = <String, OfficialWheelLibrary>{
  'linux/x64': OfficialWheelLibrary(
    target: 'linux/x64',
    version: '1.0.1',
    wheel: DownloadAsset(
      url:
          'https://files.pythonhosted.org/packages/2a/58/'
          'bdd5bada89d7a132375df05e962bf702c148b47043dca98d820d9395152b/'
          'mediapipe-1.0.1-py3-none-manylinux_2_28_x86_64.whl',
      sha256:
          '121522251afc3c135e4b7b0c341dd5e050ad1ec87631127484f3c389ae385044',
    ),
    libraryName: 'libmediapipe.so',
    librarySha256:
        'b72e6d61a79d1080d29a96ba95e3cfa3e43f6c433c0acc3bc9b3eb7ac0ba103a',
    notices: {
      'LICENSE':
          '8707eef0533987efc5b155d64761eeb6e20793f50b9bd1a68dad1cf4719d0ed8',
      'NOTICE':
          'e8e3eddc5c36d7413635455933650d7423b937185180e393f9a006bee60162e7',
    },
  ),
  'windows/x64': OfficialWheelLibrary(
    target: 'windows/x64',
    version: '1.0.0',
    wheel: DownloadAsset(
      url:
          'https://files.pythonhosted.org/packages/68/53/'
          'ffb67e668f23130aff197ec49be912be910c128b60658000d8bf263207c9/'
          'mediapipe-1.0.0-py3-none-win_amd64.whl',
      sha256:
          'da57e6719bbab05007272c91d6ca2e0e2e370709491cbe344a372f87e25cf604',
    ),
    libraryName: 'libmediapipe.dll',
    librarySha256:
        'a8970c645c8c87c25ec9965cb5c898e803c6c42f7192b7de9a0541c62ae48cef',
    notices: {
      'LICENSE':
          '8707eef0533987efc5b155d64761eeb6e20793f50b9bd1a68dad1cf4719d0ed8',
      'NOTICE':
          'd3b4a80a24a01fd445d4b70a610fd836ec3547c3a62eb835a1041956c38d9f56',
    },
  ),
};

/// Google's official wheel and unmodified library behind core's shared runtime
/// on [target] (such as `linux/x64`), or null where core has none. Reference
/// tools and tests check a same-host oracle against it.
({String version, String librarySha256, String wheelSha256})? tasksRuntimeWheel(
  String target,
) {
  if (tasksRuntimeReleases[target] case final release?) {
    return (
      version: release.version,
      librarySha256: release.upstreamLibrarySha256,
      wheelSha256: release.wheelSha256,
    );
  }
  if (tasksWheelRuntimes[target] case final runtime?) {
    return (
      version: runtime.version,
      librarySha256: runtime.librarySha256,
      wheelSha256: runtime.wheel.sha256,
    );
  }
  return null;
}

/// iOS targets where every task runs in the official iOS SDK adapter core
/// builds: Google implements every task in one MediaPipeTasksCommon, which an
/// app must hold once.
const tasksRuntimeIosTargets = {'ios/arm64', 'ios-simulator/arm64'};

/// The adapter framework's install name, which core's asset resolves to.
const tasksRuntimeIosAdapter = '@rpath/mediapipe_ios.framework/mediapipe_ios';

/// Whether core has Google's engine for [target] at all.
bool hasTasksRuntime(String target) =>
    tasksRuntimeIosTargets.contains(target) ||
    tasksWheelRuntimes.containsKey(target) ||
    tasksRuntimeReleases.containsKey(target);

/// Whether core bundles Google's engine on [target] when the app leaves
/// `mediapipe_core.tasks_runtime` unset: on iOS, Linux x64 and
/// Windows x64, where every family's tasks run on it and the vision tasks
/// would bundle the same library anyway. macOS opts in, because Google's
/// library is 95 MB there and a face-only app keeps the vision package's
/// small source-built face runtimes.
bool tasksRuntimeEnabledByDefault(String target) =>
    tasksRuntimeIosTargets.contains(target) ||
    tasksWheelRuntimes.containsKey(target);

/// Whether a family that needs Google's engine on [target] fails the build
/// when [enabled] (core's `tasks_runtime` metadata) is false: only where the
/// engine is on by default and the app turned it off.
///
/// Where it is opt-in (macOS) the family builds without its engine tasks
/// instead, and creating one throws `tasksRuntimeUnavailable`'s message. `dart
/// run` builds an app's hooks for the host with the app's settings, so an iOS
/// or Android app developed on a Mac must not need the macOS opt-in to run a
/// script.
bool tasksRuntimeMissing(String target, {required bool enabled}) =>
    !enabled && tasksRuntimeEnabledByDefault(target);

/// The build error a family reports when [tasksRuntimeMissing] holds.
String tasksRuntimeRequired(String who, String target) =>
    "$who runs on $target through Google's MediaPipe engine, which "
    'mediapipe_core bundles once for every task family. Remove '
    "tasks_runtime: false from hooks.user_defines.mediapipe_core in "
    "the app's pubspec.yaml.";

/// The release for [target], or an [UnsupportedError] naming the targets that
/// have one. Targets served from a wheel ([tasksWheelRuntimes]) have none.
TasksRuntimeRelease requireTasksRuntimeRelease(String target) {
  final release = tasksRuntimeReleases[target];
  if (release == null) {
    throw UnsupportedError(
      "Google's MediaPipe engine has no release for $target. Available "
      'targets: '
      '${[...tasksRuntimeReleases.keys, ...tasksWheelRuntimes.keys].join(', ')}.',
    );
  }
  return release;
}

/// Validates an extracted release independently of source builds.
Future<File> validateTasksRuntime(
  Directory directory, {
  required TasksRuntimeRelease release,
}) async {
  final manifest = jsonDecode(
    await File.fromUri(directory.uri.resolve('manifest.json')).readAsString(),
  );
  if (manifest is! Map<String, dynamic> ||
      manifest['origin'] != 'official-pypi-wheel' ||
      manifest['upstream_version'] != release.version ||
      manifest['upstream_sha256'] != release.wheelSha256 ||
      manifest['upstream_library'] != release.upstreamLibrary ||
      manifest['upstream_library_sha256'] != release.upstreamLibrarySha256 ||
      // Archives packaged before the field existed omit it; the pinned
      // archive digest already fixes every byte of the manifest.
      (manifest.containsKey('release') &&
          manifest['release'] != release.release) ||
      manifest['platform'] != release.platform ||
      manifest['architecture'] != release.architecture ||
      manifest['minimum_os'] != release.minimumOs ||
      manifest['sha256'] != release.librarySha256 ||
      manifest['bytes'] != release.bytes ||
      manifest['delegates'] is! List ||
      !_sameList(manifest['delegates'] as List, release.delegates)) {
    throw StateError('${release.target} runtime provenance mismatch.');
  }
  final packaging = release.packaging;
  if (manifest['files'] is! Map ||
      (packaging == null
          ? manifest.containsKey('packaging')
          : manifest['packaging'] is! Map ||
                manifest['packaging']['unchanged_payload_sha256'] !=
                    packaging.unchangedPayloadSha256 ||
                manifest['packaging']['section_layout_unchanged'] !=
                    packaging.sectionLayoutUnchanged)) {
    throw StateError(
      '${release.target} runtime packaging provenance mismatch.',
    );
  }
  for (final entry in release.files.entries) {
    final file = File.fromUri(directory.uri.resolve(entry.key));
    if ((manifest['files'] as Map)[entry.key] != entry.value ||
        (await sha256.bind(file.openRead()).first).toString() != entry.value) {
      throw StateError(
        '${release.target} runtime checksum mismatch: ${entry.key}',
      );
    }
  }
  final library = File.fromUri(directory.uri.resolve(release.libraryName));
  if (await library.length() != release.bytes) {
    throw StateError('${release.target} runtime size mismatch.');
  }
  return library;
}

bool _sameList(List actual, List<String> expected) =>
    actual.length == expected.length &&
    [
      for (var i = 0; i < actual.length; i++) actual[i] == expected[i],
    ].every((equal) => equal);

/// Downloads, verifies and extracts [release] into [cache], reusing a valid
/// extraction and repairing a damaged one from the verified archive.
///
/// [source] replaces the archive's URLs, as [downloadVerified] describes.
Future<File> downloadTasksRuntime({
  required TasksRuntimeRelease release,
  required Directory cache,
  String? source,
}) async {
  final asset = release.archive;
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(asset.sha256)) {
    throw ArgumentError('Expected an archive SHA-256 digest.');
  }
  final directory = Directory.fromUri(cache.uri.resolve('${asset.sha256}/'));
  final compressed = File.fromUri(directory.uri.resolve('runtime.tar.gz'));
  await downloadVerified(asset, compressed, source: source);
  try {
    return await validateTasksRuntime(directory, release: release);
  } on FileSystemException {
    // Incomplete extraction is repaired from the verified archive.
  } on FormatException {
    // A corrupt manifest is repaired from the verified archive.
  } on StateError {
    // Never return modified cached bytes.
  }
  final temporary = await directory.createTemp('.unpack-');
  try {
    final allowed = {...release.files.keys, 'manifest.json'};
    final seen = <String>{};
    final archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(await compressed.readAsBytes()),
      callback: (entry) {
        if (!entry.isFile ||
            entry.isSymbolicLink ||
            !allowed.contains(entry.name) ||
            !seen.add(entry.name)) {
          throw FormatException(
            'Unexpected native archive entry: ${entry.name}',
          );
        }
      },
    );
    if (!seen.containsAll(allowed)) {
      throw FormatException('${release.target} runtime archive is incomplete.');
    }
    for (final entry in archive) {
      await File.fromUri(
        temporary.uri.resolve(entry.name),
      ).writeAsBytes(entry.readBytes()!);
    }
    await validateTasksRuntime(temporary, release: release);
    // Publish the library last; concurrent extractions contain identical bytes.
    for (final name in allowed.where((name) => name != release.libraryName)) {
      await File.fromUri(
        temporary.uri.resolve(name),
      ).rename(File.fromUri(directory.uri.resolve(name)).path);
    }
    return await File.fromUri(
      temporary.uri.resolve(release.libraryName),
    ).rename(File.fromUri(directory.uri.resolve(release.libraryName)).path);
  } finally {
    await temporary.delete(recursive: true);
  }
}
