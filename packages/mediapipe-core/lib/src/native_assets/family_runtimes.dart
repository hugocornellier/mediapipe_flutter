import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

import '../../native_assets.dart';

/// The name each task family binds its own MediaPipe library under:
/// `package:mediapipe_vision/mediapipe.dylib`, `package:mediapipe_text/...`
/// and `package:mediapipe_audio/...`.
///
/// Google builds one C library per family, so an app bundles only the
/// families it depends on. The libraries keep their symbols to themselves,
/// so the three load side by side in one process.
const familyRuntimeAssetName = 'mediapipe.dylib';

/// Google's MediaPipe build that names the release holding the libraries:
/// the 1.1.0 development build of October 5, 2026. Files from Google's
/// delivery of October 8 are posted there too.
const familyRuntimeVersion = '1.1.0-dev.20261005';

/// Where the hooks download Google's libraries: a pre-release of this
/// project's native downloads, holding Google's files unmodified, posted with
/// Google's permission until Google publishes 1.1.0.
///
/// `hooks.user_defines.mediapipe_core.asset_source` replaces it for offline
/// and mirrored builds: a directory or URL holding each file under its
/// SHA-256.
const familyRuntimeBaseUrl =
    'https://github.com/hugocornellier/mediapipe_flutter_native/releases/'
    'download/per-family-v$familyRuntimeVersion';

/// One of Google's files, exactly as Google ships it.
final class FamilyRuntime {
  /// Pins [fileName] by digest and size.
  const FamilyRuntime(this.fileName, this.sha256, this.bytes);

  /// Google's file name: a library, or an XCFramework zip on iOS.
  final String fileName;

  /// SHA-256 of the only accepted bytes.
  final String sha256;

  /// Exact size in bytes.
  final int bytes;

  /// The download from [familyRuntimeBaseUrl]. Google gives several targets'
  /// libraries the same file name, so the release names each by its digest
  /// first; the hook still saves it as [fileName].
  DownloadAsset get asset => DownloadAsset(
    url: '$familyRuntimeBaseUrl/$sha256-$fileName',
    sha256: sha256,
  );
}

/// Google's per-family libraries, by family and build target.
///
/// Android has 32-bit ARM too, which Flutter's release builds include, though
/// no task claims it; browsers run Google's JavaScript runtime instead.
///
/// Android and iOS take every family from Google's delivery of October 8,
/// 2026. Its macOS and Linux vision, text and audio files are the October 5
/// bytes, and its Windows ones differ only in their build timestamp, so those
/// pins stay.
const familyRuntimes = <String, Map<String, FamilyRuntime>>{
  'vision': {
    'macos/arm64': FamilyRuntime(
      'libmediapipe_tasks_vision.dylib',
      '592cacad7df116b6645deaee48a56fbf3f42788b3067e478d12a654070a837ca',
      26560560,
    ),
    'android/arm64': FamilyRuntime(
      'libmediapipe_tasks_vision.so',
      'da82f83e43fdcbe2ffb5841c887bbb84bae10670006e2e9481d57b2503fbf17c',
      13857344,
    ),
    'android/arm': FamilyRuntime(
      'libmediapipe_tasks_vision.so',
      'fe6d7d1e8b03a6e191b3deb3d4c1c9ee0cfdecee04568152b30f0fe7b4bc65ee',
      9514268,
    ),
    'android/x64': FamilyRuntime(
      'libmediapipe_tasks_vision.so',
      '41542b554beba7dd4024d4ca547c1cca7190f4c362b805d42fb461cdffbd0624',
      16752584,
    ),
    'ios/arm64': _visionIos,
    'ios-simulator/arm64': _visionIos,
    'linux/x64': FamilyRuntime(
      'libmediapipe_tasks_vision.so',
      'bd7186c11136388f99fa51875a3c12d6a3bf2c2d061980d36d53d5beaab84d23',
      29679344,
    ),
    'windows/x64': FamilyRuntime(
      'mediapipe_tasks_vision.dll',
      '0b98a6b9d7c0e79b932d53ec80ce2183947f19e234fa657817785faaf7dd41c7',
      24688640,
    ),
  },
  'text': {
    'macos/arm64': FamilyRuntime(
      'libmediapipe_tasks_text.dylib',
      '78c35de4d7b33c9c3687057f736bc07b37e13254f5defe7c1b0fcfcf58ba6604',
      26121952,
    ),
    'android/arm64': FamilyRuntime(
      'libmediapipe_tasks_text.so',
      '0921347d773f6c4c948ab1400b85684ffd20a7fc6eb1282ba6c346e6c7fb9355',
      15385184,
    ),
    'android/arm': FamilyRuntime(
      'libmediapipe_tasks_text.so',
      '0407eb55d10cd857cf70cd6a9db2d26072d06c4affc5043a944570259e528ce7',
      10403924,
    ),
    'android/x64': FamilyRuntime(
      'libmediapipe_tasks_text.so',
      '8f710c27bd3e500789bb45188f792877826f722161dc1676df0192eeee161924',
      18587392,
    ),
    'ios/arm64': _textIos,
    'ios-simulator/arm64': _textIos,
    'linux/x64': FamilyRuntime(
      'libmediapipe_tasks_text.so',
      'e69af0bd70966f6a0e2667b89e0ba0ed5cb831c0cb23b1dc966efa5372e41bd8',
      39004944,
    ),
    'windows/x64': FamilyRuntime(
      'mediapipe_tasks_text.dll',
      '03900017f36817242f81cc35ee5d57daaaa6d89d523d56aba01e1fe20be2557a',
      44610048,
    ),
  },
  'audio': {
    'macos/arm64': FamilyRuntime(
      'libmediapipe_tasks_audio.dylib',
      '5848efb7a97e4b0c38640de5484d54e31adc19c014ab6a4e2b9e250b867df209',
      12841856,
    ),
    'android/arm64': FamilyRuntime(
      'libmediapipe_tasks_audio.so',
      '1eb2f74479a8cb4c6671b2269bcd8c9e70eb0134df655c78d4776d86def27f14',
      9110048,
    ),
    'android/arm': FamilyRuntime(
      'libmediapipe_tasks_audio.so',
      '52020d74c7dc2639a6c9fd640f8b697773520bdec75acdb725df1041f91b46d8',
      6088836,
    ),
    'android/x64': FamilyRuntime(
      'libmediapipe_tasks_audio.so',
      '9ad57acb98ece90560eadc2740e0eae271ef27cc164ddf0bd51a73364c73322a',
      11555856,
    ),
    'ios/arm64': _audioIos,
    'ios-simulator/arm64': _audioIos,
    'linux/x64': FamilyRuntime(
      'libmediapipe_tasks_audio.so',
      'a5bc7dab53fe9c42a29970791770a79bfca132613c8f08864f328ba5ef9769c3',
      20131472,
    ),
    'windows/x64': FamilyRuntime(
      'mediapipe_tasks_audio.dll',
      'f94d99a584e4cbfbc5e6a068f5b4e5a1b237218c2ee7a1ccf742b82105c7d41a',
      17534464,
    ),
  },
  // Universal Embedder and Semantic Retriever, from Google's delivery of
  // October 8, 2026, which added the retrieval and decision families.
  'retrieval': {
    'macos/arm64': FamilyRuntime(
      'libmediapipe_tasks_retrieval.dylib',
      '3d8f97a2f5e719db0866b0a26c8bf11897d817586565f459735cf8f9a29a3934',
      19237744,
    ),
    'android/arm64': FamilyRuntime(
      'libmediapipe_tasks_retrieval.so',
      '4a56a9305671e645c5c26e0e1791ed85f6f1f77176e141ac50e9194bcdd12f50',
      12297872,
    ),
    'android/arm': FamilyRuntime(
      'libmediapipe_tasks_retrieval.so',
      'af37e5bfdc2d363ad713accd332601cad7c5365d6daa2dfd4864ba0d6a4876a9',
      8386036,
    ),
    'android/x64': FamilyRuntime(
      'libmediapipe_tasks_retrieval.so',
      '05197b0dd412b947abc5479ddcb04e79b84a2786c590424f42392b878b1abf2a',
      15131376,
    ),
    'ios/arm64': _retrievalIos,
    'ios-simulator/arm64': _retrievalIos,
    'linux/x64': FamilyRuntime(
      'libmediapipe_tasks_retrieval.so',
      '1c89bfa537bbe03a90a3f07c1aa737c652098aed8df6cbf95d88c2d77e30d200',
      27678224,
    ),
    'windows/x64': FamilyRuntime(
      'mediapipe_tasks_retrieval.dll',
      '89d17f5a3c1a7a0f660267bf6354b5af2bf56f01cb0d7e917ccba15a8f0cac07',
      22322176,
    ),
  },
  // Decision Maker, from the same delivery, which has no Windows library:
  // Windows stays on the wheel's library ([wheelRuntimes]).
  'decision': {
    'macos/arm64': FamilyRuntime(
      'libmediapipe_tasks_decision.dylib',
      '41ee7b75ad4067f282fdcbc716ae93e157f36f84267ec781cd0aaac9d833d836',
      9907456,
    ),
    'android/arm64': FamilyRuntime(
      'libmediapipe_tasks_decision.so',
      '601b89b46a1793f458b63214fb32495a50a8a3bf5bf4a99e4dd58f5aac9c1642',
      7384672,
    ),
    'android/arm': FamilyRuntime(
      'libmediapipe_tasks_decision.so',
      'f5074c693a6c0d827897efe714ec3b9306ce4a0d54548e24ecb77f3cab910f44',
      4867960,
    ),
    'android/x64': FamilyRuntime(
      'libmediapipe_tasks_decision.so',
      '4c87c55486b57a48a60a6b408df1a0aaf4f2017762fb8732b1b7160895aaed65',
      9725024,
    ),
    'ios/arm64': _decisionIos,
    'ios-simulator/arm64': _decisionIos,
    'linux/x64': FamilyRuntime(
      'libmediapipe_tasks_decision.so',
      '55ae8469d7542f8623873bc3683b52382390f76ed79c9bb2271165faf6ccb49f',
      16116288,
    ),
  },
};

const _visionIos = FamilyRuntime(
  'MediaPipeTasksVisionC.xcframework.zip',
  '910013512896be0c2e3966a21137a931e6630e8e9babac99cef5fdc1f34f2794',
  62968259,
);
const _textIos = FamilyRuntime(
  'MediaPipeTasksTextC.xcframework.zip',
  '2ca0f943e2d376d089c1eeabace73399597e7be232059c88b8a607bb99103c27',
  66482595,
);
const _audioIos = FamilyRuntime(
  'MediaPipeTasksAudioC.xcframework.zip',
  'c8e6deafb6fd26df9b49a4f13516ac247b585e7a4ef7e54a526e7fedcdc4d3ac',
  32521231,
);
const _retrievalIos = FamilyRuntime(
  'MediaPipeTasksRetrievalC.xcframework.zip',
  '507e8f7ae9931b777cf44cb0b695dd1455ccb67cac1868eca5e49f276ced632c',
  45006655,
);
const _decisionIos = FamilyRuntime(
  'MediaPipeTasksDecisionC.xcframework.zip',
  'db5f540c8359da2628fd5e727a50ec0aaa1dd9f5e8aa120d634d0f7ff402f4f9',
  26197715,
);

/// Google's MediaPipe library as it ships inside one of Google's official
/// Python wheels, which holds every task Google's Python API serves. A family
/// whose own library Google has not built yet bundles this instead; when
/// Google's arrives, the family moves to [familyRuntimes] and its bindings
/// stay the same, since both libraries export the same C API.
final class WheelRuntime {
  /// Pins [path] inside [wheel] by digest and size.
  const WheelRuntime(this.wheel, this.path, this.sha256, this.bytes);

  /// Google's wheel on PyPI, pinned by its SHA-256.
  final DownloadAsset wheel;

  /// The library's path inside the wheel.
  final String path;

  /// SHA-256 of the only accepted library bytes.
  final String sha256;

  /// Exact size of the library in bytes.
  final int bytes;
}

// TODO: Retire this table and bundleWheelRuntime once Google builds a
// Windows decision library: its delivery of October 8, 2026 has every other
// target, pinned in familyRuntimes. See
// packages/mediapipe-core/tool/PER_FAMILY_RUNTIMES.md.

/// The families that bundle Google's wheel library ([WheelRuntime]), by
/// family and build target: Decision Maker on Windows, the one target
/// Google's per-family delivery lacks. Google's 1.1.0 wheels (October 6,
/// 2026) are the only official C library with it there.
const wheelRuntimes = <String, Map<String, WheelRuntime>>{
  'decision': {
    'windows/x64': WheelRuntime(
      DownloadAsset(
        url:
            'https://files.pythonhosted.org/packages/4a/95/'
            '14e45f779280d2cc9d7495cb149a67f8a44d5beb801df7f662353976d0ae/'
            'mediapipe-1.1.0-py3-none-win_amd64.whl',
        sha256:
            '955ac7934825aa8c8ff78fd1e47bf1f2b78fcafc95a8ebc010f6ee977c2eaf53',
      ),
      'mediapipe/tasks/c/libmediapipe.dll',
      '8c74fb9c004f81fc1e808cc7fec8e91baeb6d61934b09a42cb757de38d4f6a5d',
      60979200,
    ),
  },
};

/// [family]'s library for [target], or an [UnsupportedError] naming the
/// targets that have one.
FamilyRuntime requireFamilyRuntime(String family, String target) {
  final runtimes = familyRuntimes[family];
  if (runtimes == null) throw ArgumentError.value(family, 'family');
  final runtime = runtimes[target];
  if (runtime != null) return runtime;
  throw UnsupportedError(_unsupportedTarget(family, target, runtimes.keys));
}

String _unsupportedTarget(
  String family,
  String target,
  Iterable<String> targets,
) => switch (target) {
  // Flutter's macOS release and profile builds include Intel unless the
  // app excludes it; debug builds target only the host.
  'macos/x64' =>
    'mediapipe_$family has no MediaPipe library for Intel Macs '
        "(macos/x64), and Flutter's macOS release and profile builds "
        'include Intel by default. Build the app for Apple Silicon only: add '
        'ARCHS = arm64 and EXCLUDED_ARCHS = x86_64 to '
        'macos/Runner/Configs/AppInfo.xcconfig, or run '
        '`flutter config --enable-macos-arm64-only`.',
  'ios-simulator/x64' =>
    'mediapipe_$family has no MediaPipe library for the Intel iOS '
        'Simulator (ios-simulator/x64). Exclude that slice in the Runner '
        "target's build settings: "
        'EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64.',
  _ =>
    'mediapipe_$family has no MediaPipe library for $target. Targets: '
        '${targets.join(', ')}, plus browsers through Google\'s '
        'JavaScript runtime.',
};

/// The lowest Android API level Google's Android libraries load on: they are
/// built for Android 9.
const familyRuntimeMinimumAndroidApi = 28;

/// Bundles [family]'s library for the hook's target under
/// [familyRuntimeAssetName], in the calling family's package.
Future<void> bundleFamilyRuntime(
  BuildInput input,
  BuildOutputBuilder output, {
  required String family,
}) async {
  final code = input.config.code;
  requireDynamicLinking(code);
  final target = buildTarget(code);
  final runtime = requireFamilyRuntime(family, target);
  if (code.targetOS == OS.android &&
      code.android.targetNdkApi < familyRuntimeMinimumAndroidApi) {
    throw UnsupportedError(
      "mediapipe_$family runs Google's MediaPipe library, which needs Android "
      '9 (API $familyRuntimeMinimumAndroidApi); this app targets API '
      '${code.android.targetNdkApi}. Set minSdk = '
      '$familyRuntimeMinimumAndroidApi in android/app/build.gradle(.kts).',
    );
  }
  final source = hookAssetSource(input);
  final cache = Directory.fromUri(
    input.outputDirectoryShared.resolve('${runtime.sha256}/'),
  );
  final download = await downloadVerified(
    runtime.asset,
    File.fromUri(cache.uri.resolve(runtime.fileName)),
    source: source,
  );
  if (await download.length() != runtime.bytes) {
    throw StateError('$target $family runtime size mismatch.');
  }
  final library = switch (code.targetOS) {
    OS.macOS => await _prepareMacos(download),
    OS.iOS => await _extractIosSlice(
      download,
      simulator: code.iOS.targetSdk == IOSSdk.iPhoneSimulator,
    ),
    _ => download,
  };
  output.dependencies.add(download.uri);
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: familyRuntimeAssetName,
      linkMode: DynamicLoadingBundled(),
      file: library.uri,
    ),
  );
}

/// Bundles [family]'s library from Google's wheel ([wheelRuntimes]) for the
/// hook's target under [familyRuntimeAssetName], in the calling family's
/// package, as [bundleFamilyRuntime] bundles a per-family library. A target
/// with neither gets nothing on Android and iOS, so the family's tasks report
/// it unsupported instead of failing the app's build.
Future<void> bundleWheelRuntime(
  BuildInput input,
  BuildOutputBuilder output, {
  required String family,
}) async {
  final code = input.config.code;
  requireDynamicLinking(code);
  final runtimes = wheelRuntimes[family];
  if (runtimes == null) throw ArgumentError.value(family, 'family');
  final target = buildTarget(code);
  final runtime = runtimes[target];
  if (runtime == null) {
    if (code.targetOS == OS.android || code.targetOS == OS.iOS) return;
    throw UnsupportedError(_unsupportedTarget(family, target, runtimes.keys));
  }
  final wheelName = Uri.parse(runtime.wheel.url).pathSegments.last;
  final cache = Directory.fromUri(
    input.outputDirectoryShared.resolve('${runtime.wheel.sha256}/'),
  );
  final wheel = await downloadVerified(
    runtime.wheel,
    File.fromUri(cache.uri.resolve(wheelName)),
    source: hookAssetSource(input),
  );
  final extracted = await _derived(
    wheel,
    'library/${runtime.path.split('/').last}',
    (copy) async {
      final entry = ZipDecoder()
          .decodeBytes(await wheel.readAsBytes())
          .findFile(runtime.path);
      if (entry == null) {
        throw StateError('${wheel.path} has no ${runtime.path}.');
      }
      await copy.writeAsBytes(entry.readBytes()!, flush: true);
      if (await copy.length() != runtime.bytes ||
          await _digest(copy) != runtime.sha256) {
        throw StateError(
          '$target $family wheel library does not match its pin.',
        );
      }
    },
  );
  final library = code.targetOS == OS.macOS
      ? await _prepareMacos(extracted)
      : extracted;
  output.dependencies.add(wheel.uri);
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: familyRuntimeAssetName,
      linkMode: DynamicLoadingBundled(),
      file: library.uri,
    ),
  );
}

/// A copy of Google's macOS library with room for a longer install name.
///
/// Dart and Flutter rename every bundled library, but Google's macOS builds
/// leave 40 to 80 bytes of header room, so the rename fails ("larger updated
/// load commands do not fit"). Naming the system frameworks without their
/// `Versions/A/` directory, which macOS resolves to the same file, frees
/// about 150 bytes. Google's iOS device builds carry about 12 KB; until the
/// macOS ones are linked with `-headerpad_max_install_names` as well, this
/// copy stands in. Only load commands and the ad hoc signature change.
Future<File> _prepareMacos(File library) => _derived(
  library,
  'header-room/${library.uri.pathSegments.last}',
  (copy) async {
    final listing = await _run('xcrun', ['otool', '-L', copy.path]);
    final changes = <String>[];
    for (final match in _versionedFramework.allMatches(listing)) {
      changes.addAll([
        '-change',
        match[0]!,
        '/System/Library/Frameworks/${match[1]}.framework/${match[1]}',
      ]);
    }
    if (changes.isNotEmpty) {
      await _run('xcrun', ['install_name_tool', ...changes, copy.path]);
    }
    await _run('codesign', ['--force', '--sign', '-', copy.path]);
  },
);

final _versionedFramework = RegExp(
  r'/System/Library/Frameworks/(\w+)\.framework/Versions/[A-Z]/\1',
);

/// The arm64 device or simulator binary from Google's XCFramework zip.
///
/// It keeps Google's file name, which Flutter names the framework after: the
/// simulator builds have no header room for a longer install name.
Future<File> _extractIosSlice(File zip, {required bool simulator}) {
  final name = zip.uri.pathSegments.last.replaceFirst('.xcframework.zip', '');
  final slice = simulator ? 'ios-arm64_x86_64-simulator' : 'ios-arm64';
  return _derived(zip, '${simulator ? 'simulator' : 'device'}/$name', (
    copy,
  ) async {
    final path = '$name.xcframework/$slice/$name.framework/$name';
    final entry = ZipDecoder()
        .decodeBytes(await zip.readAsBytes())
        .findFile(path);
    if (entry == null) throw StateError('${zip.path} has no $path.');
    await copy.writeAsBytes(entry.readBytes()!, flush: true);
    // The simulator binary also holds x86_64; a hook bundles one
    // architecture.
    if (simulator) {
      await _run('xcrun', [
        'lipo',
        copy.path,
        '-thin',
        'arm64',
        '-output',
        copy.path,
      ]);
    }
  });
}

/// [name] derived from the verified [source] by [prepare], made once and
/// reused only while its bytes match the digest recorded when it was made.
Future<File> _derived(
  File source,
  String name,
  Future<void> Function(File copy) prepare,
) async {
  final file = File.fromUri(source.parent.uri.resolve(name));
  final record = File('${file.path}.sha256');
  if (await file.exists() && await record.exists()) {
    if (await _digest(file) == (await record.readAsString()).trim()) {
      return file;
    }
  }
  await file.parent.create(recursive: true);
  final temporary = await file.parent.createTemp('.prepare-');
  try {
    final copy = File.fromUri(
      temporary.uri.resolve(file.uri.pathSegments.last),
    );
    await source.copy(copy.path);
    await prepare(copy);
    await record.writeAsString(await _digest(copy));
    return await copy.rename(file.path);
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<String> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed (${result.exitCode}):\n'
      '${result.stderr}',
    );
  }
  return result.stdout as String;
}
