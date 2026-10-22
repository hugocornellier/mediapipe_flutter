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

/// Google's MediaPipe build that names the mirror release holding the
/// libraries: the 1.2.0 nightly build of October 21, 2026.
const familyRuntimeVersion = '1.2.0-nightly.20261021';

/// Google's archive of the October 21, 2026 build, where the hooks download
/// Google's libraries: each one is read from it with HTTP range requests,
/// without the rest of the archive.
const familyRuntimeArchiveUrl =
    'https://storage.googleapis.com/mediapipe-assets/prebuilts/'
    'mediapipe_tasks_c/20261021/mediapipe_tasks_c_20261021.zip';

/// The hooks' mirror of [familyRuntimeArchiveUrl]: a pre-release of this
/// project's native downloads, holding Google's files unmodified, posted with
/// Google's permission.
///
/// `hooks.user_defines.mediapipe_core.asset_source` replaces both for offline
/// and mirrored builds: a directory or URL holding each file under its
/// SHA-256.
const familyRuntimeBaseUrl =
    'https://github.com/hugocornellier/mediapipe_flutter_native/releases/'
    'download/per-family-v$familyRuntimeVersion';

/// One of Google's files, exactly as Google ships it.
final class FamilyRuntime {
  /// Pins the file at [path] in Google's archive by digest and size.
  const FamilyRuntime(this.path, this.sha256, this.bytes);

  /// Where the file is in [familyRuntimeArchiveUrl], such as
  /// `vision/darwin_arm64/libmediapipe_tasks_vision.dylib`.
  final String path;

  /// Google's file name: a library, or a framework zip on iOS.
  String get fileName => path.substring(path.lastIndexOf('/') + 1);

  /// SHA-256 of the only accepted bytes.
  final String sha256;

  /// Exact size in bytes.
  final int bytes;

  /// The download: the file in Google's archive, then the copy at
  /// [familyRuntimeBaseUrl]. Google gives several targets' libraries the
  /// same file name, so the mirror names each by its digest first; the hook
  /// still saves it as [fileName].
  DownloadAsset get asset => DownloadAsset(
    url: '$familyRuntimeArchiveUrl#$path',
    sha256: sha256,
    mirrors: ['$familyRuntimeBaseUrl/$sha256-$fileName'],
  );
}

/// Google's per-family libraries, by family and build target.
///
/// Android has 32-bit ARM too, which Flutter's release builds include, though
/// no task claims it; browsers run Google's JavaScript runtime instead.
///
/// Every file comes from Google's nightly build of October 21, 2026
/// (MediaPipe 1.2.0), unmodified. iOS has one framework zip for devices and
/// one for the Simulator.
const familyRuntimes = <String, Map<String, FamilyRuntime>>{
  'vision': {
    'macos/arm64': FamilyRuntime(
      'vision/darwin_arm64/libmediapipe_tasks_vision.dylib',
      '3e0436f2ffbfdfc8b60667dce7c8a4f860f7b67f0db8b048989e41fdf897e69b',
      27037264,
    ),
    'android/arm64': FamilyRuntime(
      'vision/android_arm64-v8a/libmediapipe_tasks_vision.so',
      'b9f7656367439ddb7ba01c81e4b4c92fd3ca82c9fe0a84b0b447dc1191a6a0ff',
      13838416,
    ),
    'android/arm': FamilyRuntime(
      'vision/android_armeabi-v7a/libmediapipe_tasks_vision.so',
      'a6d60faae81d66c4f4674f3595c54b5981df36c423c6fa5429e4bc4adf3f3422',
      9798620,
    ),
    'android/x64': FamilyRuntime(
      'vision/android_x86_64/libmediapipe_tasks_vision.so',
      '32988dda2d2e033f06db4420d669d708534490d9d0018091ae03d825bddebac8',
      17257688,
    ),
    'ios/arm64': FamilyRuntime(
      'vision/ios_arm64/MediaPipeTasksVisionC.framework.zip',
      'c4588ee91d0615fe5c3e0957c82707068f9c40daf31fcd1044c35dea9667bc88',
      8010534,
    ),
    'ios-simulator/arm64': FamilyRuntime(
      'vision/ios_simulator/MediaPipeTasksVisionC.framework.zip',
      '65cff23f313b1cc63a216d2fb982fc1e2ac63d12ed84400e897f00da27a40859',
      17607461,
    ),
    'linux/x64': FamilyRuntime(
      'vision/linux_x86_64/libmediapipe_tasks_vision.so',
      '00f9c870c85a58bd9f119dbd9d2e8b4b1b90131ff0cf6f43276f2b3d37fda15a',
      30563904,
    ),
    'windows/x64': FamilyRuntime(
      'vision/windows_x86_64/mediapipe_tasks_vision.dll',
      'fd0b9876a628ef23b566909dede0153c98dd75a24a92dbe21c72a138af4eb3ae',
      25217024,
    ),
  },
  'text': {
    'macos/arm64': FamilyRuntime(
      'text/darwin_arm64/libmediapipe_tasks_text.dylib',
      '23e9a725fbf8f43cec75ce1ca84f22215a82d3dbaee920ca322d8f05297b38d3',
      25389712,
    ),
    'android/arm64': FamilyRuntime(
      'text/android_arm64-v8a/libmediapipe_tasks_text.so',
      '8cc9510ea814fdb73ca6601315f602ce8ad85e16b85be58bf193130e4e214cc9',
      14856896,
    ),
    'android/arm': FamilyRuntime(
      'text/android_armeabi-v7a/libmediapipe_tasks_text.so',
      'c5cd8c292e6be178984b2644c131058c7551f9166bca6a5a8f5f2b412636d333',
      10176472,
    ),
    'android/x64': FamilyRuntime(
      'text/android_x86_64/libmediapipe_tasks_text.so',
      '7c4967737ae427ea9e70253cddfaf6426c974134aa15c449bb48a80f4fa5bfd8',
      18255760,
    ),
    'ios/arm64': FamilyRuntime(
      'text/ios_arm64/MediaPipeTasksTextC.framework.zip',
      '2e372aa66d3479375a8fac788c0da985433f540bcce3b9ea00c1a06aa41af925',
      8374313,
    ),
    'ios-simulator/arm64': FamilyRuntime(
      'text/ios_simulator/MediaPipeTasksTextC.framework.zip',
      '4f878ad2e306d8617fa47b44ae35c079f7ee876c11ed12c8a44e85229ab5c6ab',
      18135643,
    ),
    'linux/x64': FamilyRuntime(
      'text/linux_x86_64/libmediapipe_tasks_text.so',
      '75352eef70b5052993eb384f0559f6c089757825d4679d1d74f7b8a07a56efe6',
      38439520,
    ),
    'windows/x64': FamilyRuntime(
      'text/windows_x86_64/mediapipe_tasks_text.dll',
      '6ec12531153a215700efb0e6877211f3dc122066290ef4f77d952557853f93ad',
      37666816,
    ),
  },
  'audio': {
    'macos/arm64': FamilyRuntime(
      'audio/darwin_arm64/libmediapipe_tasks_audio.dylib',
      'cd9e492d338b5e6c22fb124c8eccaeb694fb64e748688da8b706e263a4e77739',
      12625792,
    ),
    'android/arm64': FamilyRuntime(
      'audio/android_arm64-v8a/libmediapipe_tasks_audio.so',
      'd13dd9af98f182499db26fa283f8632b9f786a8f6f628421e849fa8abaac6217',
      8957528,
    ),
    'android/arm': FamilyRuntime(
      'audio/android_armeabi-v7a/libmediapipe_tasks_audio.so',
      'ea1645978003c6fea4f40c3a139b396e78395189f339f86960178b3af88daf92',
      6073916,
    ),
    'android/x64': FamilyRuntime(
      'audio/android_x86_64/libmediapipe_tasks_audio.so',
      '2b3563c3720f2fbff87431ec770669d5a6771cc7e905d92fbdebb711bc3c357d',
      11566368,
    ),
    'ios/arm64': FamilyRuntime(
      'audio/ios_arm64/MediaPipeTasksAudioC.framework.zip',
      'ce389899ee486de25a3bf3bd1203f7ad544038afd03c64628d26ae3b1d5fa672',
      4040155,
    ),
    'ios-simulator/arm64': FamilyRuntime(
      'audio/ios_simulator/MediaPipeTasksAudioC.framework.zip',
      '6893d71184bf55981e6abf4f05425a43481275e43fcf87021fe4719ac8952358',
      9178923,
    ),
    'linux/x64': FamilyRuntime(
      'audio/linux_x86_64/libmediapipe_tasks_audio.so',
      'dec2be2d745bb690b89f8a346f52ff06a51b5990d384630213f5d03552758b73',
      19834976,
    ),
    'windows/x64': FamilyRuntime(
      'audio/windows_x86_64/mediapipe_tasks_audio.dll',
      '8515c56800c3ec502488dac7bb7966b332d85f5e631ff7830fd5f2a3b8b4988f',
      17048576,
    ),
  },
  'retrieval': {
    'macos/arm64': FamilyRuntime(
      'retrieval/darwin_arm64/libmediapipe_tasks_retrieval.dylib',
      '5e6b2de996a4faf12d3380e931827dea5b868364c5bb1207e4982d5933dcc9af',
      19666064,
    ),
    'android/arm64': FamilyRuntime(
      'retrieval/android_arm64-v8a/libmediapipe_tasks_retrieval.so',
      'c6c1c9afca99249587f8d177bc7bc24a3f5ce66e1429d9367b04a1f6feb692ec',
      12401664,
    ),
    'android/arm': FamilyRuntime(
      'retrieval/android_armeabi-v7a/libmediapipe_tasks_retrieval.so',
      '1ef88ffdd075bd8a3be4af577c723749b4c34adf99bb3192aa8f2639e201dc8a',
      8695180,
    ),
    'android/x64': FamilyRuntime(
      'retrieval/android_x86_64/libmediapipe_tasks_retrieval.so',
      '2fd74d57a36283ec426cbc520be75baf5753adbd260356fc8c22a0615ebcd512',
      15660160,
    ),
    'ios/arm64': FamilyRuntime(
      'retrieval/ios_arm64/MediaPipeTasksRetrievalC.framework.zip',
      '527602875e8000419023586dfc1a3d403312e87662216ee1259916f2876fe3d8',
      5894716,
    ),
    'ios-simulator/arm64': FamilyRuntime(
      'retrieval/ios_simulator/MediaPipeTasksRetrievalC.framework.zip',
      '9e2a1f23c87ad5d38b028b266adb9fa94eff6bed728a30d7f743b0f1377e0f6e',
      13247539,
    ),
    'linux/x64': FamilyRuntime(
      'retrieval/linux_x86_64/libmediapipe_tasks_retrieval.so',
      '0f5ab057ba8df6177e948d188f4975021c2ac4f9c007dcf525200d95e91ee0b1',
      28648480,
    ),
    'windows/x64': FamilyRuntime(
      'retrieval/windows_x86_64/mediapipe_tasks_retrieval.dll',
      'cbc17497c9ec86f0a578607767f7b116178914eb969dd188dc81509618a4a886',
      22878208,
    ),
  },
  'decision': {
    'macos/arm64': FamilyRuntime(
      'decision/darwin_arm64/libmediapipe_tasks_decision.dylib',
      'b52de3ca0e7dd77c8c9a4e0eced82d1310104cf4092f8ae3604b55c90c0fbcf8',
      11329696,
    ),
    'android/arm64': FamilyRuntime(
      'decision/android_arm64-v8a/libmediapipe_tasks_decision.so',
      '20af566cefb696c94179cdc5e6c8f20733931c310e63ec06bf33aea99f7e5276',
      15354328,
    ),
    'android/arm': FamilyRuntime(
      'decision/android_armeabi-v7a/libmediapipe_tasks_decision.so',
      'c1236ff36a4ef23f784e7a3295880ad9abfc4c5ba2cfdbc3a0043aea3ca11142',
      10778940,
    ),
    'android/x64': FamilyRuntime(
      'decision/android_x86_64/libmediapipe_tasks_decision.so',
      '10934b6e7a82302875c4f26bbdc5daa119f0b354d02c10ac354b07873c0bd910',
      18738656,
    ),
    'ios/arm64': FamilyRuntime(
      'decision/ios_arm64/MediaPipeTasksDecisionC.framework.zip',
      'e4d5c2ed26b0acdfaaf0ddf20c7bebd619fb07c58a51aafecd9a98587f2005a5',
      5269713,
    ),
    'ios-simulator/arm64': FamilyRuntime(
      'decision/ios_simulator/MediaPipeTasksDecisionC.framework.zip',
      '9ee5c5c8bf3baf5ba594b3d41d624196fdf8c22d829e51f4b0499413141dba21',
      11711549,
    ),
    'linux/x64': FamilyRuntime(
      'decision/linux_x86_64/libmediapipe_tasks_decision.so',
      'ecf2a8c5d7b30754d61806d1a1a5ea6a002f037d11d8d04298ebb4c4313d57ef',
      32227120,
    ),
    'windows/x64': FamilyRuntime(
      'decision/windows_x86_64/mediapipe_tasks_decision.dll',
      'c4246920eb44c7e1e6efde11637fe03a8ebd39a572ff602d95a5e82b61e439b2',
      34275840,
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
/// [familyRuntimeAssetName], in the calling family's package: Google's
/// per-family library ([familyRuntimes]).
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
