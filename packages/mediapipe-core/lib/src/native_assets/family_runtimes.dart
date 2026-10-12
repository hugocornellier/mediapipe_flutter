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
/// the 1.1.1 development build of October 9, 2026.
const familyRuntimeVersion = '1.1.1-dev.20261009';

/// Where the hooks download Google's libraries: a pre-release of this
/// project's native downloads, holding Google's files unmodified, posted with
/// Google's permission until Google publishes them.
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

  /// Google's file name: a library, or a framework zip on iOS.
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
/// Every file comes from Google's 1.1.1 development build of October 9, 2026,
/// unmodified. iOS has one framework zip for devices and one for the
/// Simulator.
const familyRuntimes = <String, Map<String, FamilyRuntime>>{
  'vision': {
    'macos/arm64': FamilyRuntime(
      'libmediapipe_tasks_vision.dylib',
      '1631338159bb91f74df15ea7fc606d2ca66680ebcb512baf93ae27f05d0269d1',
      26326640,
    ),
    'android/arm64': FamilyRuntime(
      'libmediapipe_tasks_vision.so',
      '53527c51a37578d568e6f4da81a50b322bc256167d6a91136373789662ec1a78',
      13415144,
    ),
    'android/arm': FamilyRuntime(
      'libmediapipe_tasks_vision.so',
      '1d65d948058140fd8bf10860fec209f8e65c2e6f805e3b53a19d93ed872462a2',
      9406796,
    ),
    'android/x64': FamilyRuntime(
      'libmediapipe_tasks_vision.so',
      'e556f9c0d87f7509ceaddb6d7923702dad09e9a2060f121c4d9c2cbea4d70de0',
      16573320,
    ),
    'ios/arm64': FamilyRuntime(
      'MediaPipeTasksVisionC.framework.zip',
      '2cc01b564ff0a70e7efdde59bf8c64216a3600cb39711b58480deed123812722',
      7822529,
    ),
    'ios-simulator/arm64': FamilyRuntime(
      'MediaPipeTasksVisionC.framework.zip',
      'f7128240f061a91434327b2fbdf2adafe175c97fbfbddbd400fbbf211a830eeb',
      17017755,
    ),
    'linux/x64': FamilyRuntime(
      'libmediapipe_tasks_vision.so',
      '5d6c88428f3369ea4af4d28f24150688f1f553776356590101bd6541dec95519',
      29374912,
    ),
    'windows/x64': FamilyRuntime(
      'mediapipe_tasks_vision.dll',
      'c3dbd1efd98ac102c7df66e8d20ae335eee058c87aaaa459156c5b44d36fff39',
      24088064,
    ),
  },
  'text': {
    'macos/arm64': FamilyRuntime(
      'libmediapipe_tasks_text.dylib',
      '192612b3c891a144b88b0ed61f1a650918f65c1711dcdcd6dd673f007e41c6cf',
      25041936,
    ),
    'android/arm64': FamilyRuntime(
      'libmediapipe_tasks_text.so',
      '2fa7e80417a5e6dbe269240c63f5c3040c1dd1af0d5730b459b384b03425a771',
      14638184,
    ),
    'android/arm': FamilyRuntime(
      'libmediapipe_tasks_text.so',
      '34a179ef6f386b13c5a14e766265a3f88d38589c04c9827edd429662b1034ab7',
      10016900,
    ),
    'android/x64': FamilyRuntime(
      'libmediapipe_tasks_text.so',
      '468decef4dde90f5f83331133f2f887b08ea0ca523020e6fb339b03ca9256e8e',
      17988672,
    ),
    'ios/arm64': FamilyRuntime(
      'MediaPipeTasksTextC.framework.zip',
      '9ca52e37c9d136d544c559f832a97f1f46749141cf02b6a3a9953a059fb5f9ed',
      8220504,
    ),
    'ios-simulator/arm64': FamilyRuntime(
      'MediaPipeTasksTextC.framework.zip',
      '197c5b51d39189195e64a9de46bc79ca0cbc87681cf4db29828801af848e49c6',
      17780508,
    ),
    'linux/x64': FamilyRuntime(
      'libmediapipe_tasks_text.so',
      '16cf9c7e4f917b6fcc78a8c9bcce26085a8a87f619ef4d1e37838fc573c8cb27',
      38238304,
    ),
    'windows/x64': FamilyRuntime(
      'mediapipe_tasks_text.dll',
      'aec6c671726c35d706e36cf4e5e951fbe021388823efd2a423d4722028882933',
      37355520,
    ),
  },
  'audio': {
    'macos/arm64': FamilyRuntime(
      'libmediapipe_tasks_audio.dylib',
      '7b7f4c9b09dd9e0ac6ed504cab187b000043cb142b17ec4a3cd59bf9857e5d9d',
      12592512,
    ),
    'android/arm64': FamilyRuntime(
      'libmediapipe_tasks_audio.so',
      '0a031886aff162adc35ce85a328e41abd8bafc9989967a2518ae18daa5b42a46',
      8839512,
    ),
    'android/arm': FamilyRuntime(
      'libmediapipe_tasks_audio.so',
      'dc26ed3554e9807f6a769bfedb907f7981c606e47c95bf802172a5108c9f07d0',
      5997940,
    ),
    'android/x64': FamilyRuntime(
      'libmediapipe_tasks_audio.so',
      'bae6df523f084e0c4852a051e826de951bda8bdb4e3d9e9b752b225e0ab701e6',
      11416528,
    ),
    'ios/arm64': FamilyRuntime(
      'MediaPipeTasksAudioC.framework.zip',
      'c14914ee225b0364a6455533aa8e00755a11aa4a23d35345323fbf694de8ba2c',
      3990222,
    ),
    'ios-simulator/arm64': FamilyRuntime(
      'MediaPipeTasksAudioC.framework.zip',
      '0e18d73a381e04b6642de3ed303c9697b170f2f51745cfce9b21265c83b6bb7c',
      9029022,
    ),
    'linux/x64': FamilyRuntime(
      'libmediapipe_tasks_audio.so',
      '9163dd2f2219dc93c0aa156d0399f48abc68eff451dd51e5796cc6f575bbb321',
      19793248,
    ),
    'windows/x64': FamilyRuntime(
      'mediapipe_tasks_audio.dll',
      '62bb1212eb68d9a0f31be0d01b7fe06232707bdb87517ea4d1705ea64d56bb43',
      16985600,
    ),
  },
  'retrieval': {
    'macos/arm64': FamilyRuntime(
      'libmediapipe_tasks_retrieval.dylib',
      '5e4a4269436d3a00aec6edc1e859273360fd176d0df01245f812a66c2ec4f6f2',
      19037968,
    ),
    'android/arm64': FamilyRuntime(
      'libmediapipe_tasks_retrieval.so',
      'baf8ce4adb63b5967ea6685765f2236b58eb77b97715cdf8d1bac33e7618093e',
      11962400,
    ),
    'android/arm': FamilyRuntime(
      'libmediapipe_tasks_retrieval.so',
      '48e256ceb2afd545cd19fdc57274357f8d37b6843e75d1d893ba086f74be666c',
      8295500,
    ),
    'android/x64': FamilyRuntime(
      'libmediapipe_tasks_retrieval.so',
      'a81831289812d853da47b8c70f2e595e71e52122197648d604d20bf3adb3947a',
      14976176,
    ),
    'ios/arm64': FamilyRuntime(
      'MediaPipeTasksRetrievalC.framework.zip',
      'c5eaf071a37213ce7aab0a6d4c30259d8d12f818e98bfb608affeb6458d7e71e',
      5730401,
    ),
    'ios-simulator/arm64': FamilyRuntime(
      'MediaPipeTasksRetrievalC.framework.zip',
      'b6fce9ce25d4f6f3a0a1442928dc14284fea442948c608f15ff4304fb5af89f4',
      12698868,
    ),
    'linux/x64': FamilyRuntime(
      'libmediapipe_tasks_retrieval.so',
      'b517d70a786788bedba90ef7eeb8634e5a324ffee5b55b4ac20a9288b7dbb57d',
      27458208,
    ),
    'windows/x64': FamilyRuntime(
      'mediapipe_tasks_retrieval.dll',
      '12dfa699780955f95749f2bb92d4356c6c255b20d3ca54955e484e9207e7a9ad',
      21771264,
    ),
  },
  // Google's build has no Windows decision library: Windows stays on the
  // wheel's library ([wheelRuntimes]).
  'decision': {
    'macos/arm64': FamilyRuntime(
      'libmediapipe_tasks_decision.dylib',
      'd1a6c23baa9fbe194cd033db470cd97bd0438995319371fea5b12904cffa7a73',
      16507328,
    ),
    'android/arm64': FamilyRuntime(
      'libmediapipe_tasks_decision.so',
      'd50250289299e6f3ffc4122d833551e398c307926a145a3bc0818c58cd091147',
      15138736,
    ),
    'android/arm': FamilyRuntime(
      'libmediapipe_tasks_decision.so',
      'ecf84dce0a89686bba785c6facd1569c37a8701361a287bae52f8182913f0a29',
      10604676,
    ),
    'android/x64': FamilyRuntime(
      'libmediapipe_tasks_decision.so',
      'bee651e784f55eb19fd87eca9ff59509a84f3f316d55a5b4e0c659425cd114cf',
      18474512,
    ),
    'ios/arm64': FamilyRuntime(
      'MediaPipeTasksDecisionC.framework.zip',
      '111d94f2bbc54d680e946e4c9bf3c29ff91b954e1803301558e4cf3522cf2bd8',
      5175893,
    ),
    'ios-simulator/arm64': FamilyRuntime(
      'MediaPipeTasksDecisionC.framework.zip',
      'd52afac86932f571b896d8dfebeaa0c3b8e2b2b5c4e6cd370b15a5c914e03101',
      11471516,
    ),
    'linux/x64': FamilyRuntime(
      'libmediapipe_tasks_decision.so',
      '245b4b8fee73aeadb81f07ba63e15ad6e24a9a81486f481d87e44a08504023a0',
      32108912,
    ),
  },
};

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
// Windows decision library: its build of October 9, 2026 has every other
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
  final library = code.targetOS == OS.iOS
      ? await _extractIosBinary(
          download,
          simulator: code.iOS.targetSdk == IOSSdk.iPhoneSimulator,
        )
      : download;
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
  output.dependencies.add(wheel.uri);
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: familyRuntimeAssetName,
      linkMode: DynamicLoadingBundled(),
      file: extracted.uri,
    ),
  );
}

/// The arm64 binary from Google's framework zip for an iOS device or the
/// Simulator.
///
/// It keeps Google's file name, which Flutter names the framework after.
Future<File> _extractIosBinary(File zip, {required bool simulator}) {
  final name = zip.uri.pathSegments.last.replaceFirst('.framework.zip', '');
  return _derived(zip, '${simulator ? 'simulator' : 'device'}/$name', (
    copy,
  ) async {
    final path = '$name.framework/$name';
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
