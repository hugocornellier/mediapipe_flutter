import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';

/// Tasks implemented by the adapter to Google's prebuilt iOS SDK.
const officialIosTasks = {
  'face_detector',
  'face_landmarker',
  'gesture_recognizer',
  'hand_landmarker',
  'holistic_landmarker',
  'image_classifier',
  'image_embedder',
  'image_segmenter',
  'interactive_segmenter',
  'interactive_segmenter_legacy',
  'object_detector',
  'pose_landmarker',
};

/// Google 1.0.1 XCFrameworks, pinned from upstream's Package.swift.
/// Inference code is linked from these binaries, never compiled from source.
/// MediaPipeTasksCommon implements every task's Objective-C classes; the Text
/// and Audio frameworks carry only their headers, which the adapter's text
/// and audio bridges compile against.
const officialIosSdkArchives = <String, DownloadAsset>{
  'MediaPipeTasksVision': (
    url:
        'https://dl.google.com/cpdc/20260911-163655/'
        'MediaPipeTasksVision-1.0.1.xcframework.zip',
    sha256: '3ea09537d103c97ac4d40daf0b672e374ca7894fbba7fada037a8975936b9a1d',
  ),
  'MediaPipeTasksCommon': (
    url:
        'https://dl.google.com/cpdc/20260911-163655/'
        'MediaPipeTasksCommon-1.0.1.xcframework.zip',
    sha256: '5c4a6a9f4c866e8456178f0707110a05484caa50e69c1d4c4e0d76d296f08e13',
  ),
  'MediaPipeTaskGraphs_library': (
    url:
        'https://dl.google.com/cpdc/20260911-163655/'
        'MediaPipeTaskGraphs-1.0.1.xcframework.zip',
    sha256: '673e8f5be771dd54374e90224e1ac3a0a0ac0bbb686201595d9b6c49cb21378d',
  ),
  'MediaPipeTasksText': (
    url:
        'https://dl.google.com/cpdc/20260911-163655/'
        'MediaPipeTasksText-1.0.1.xcframework.zip',
    sha256: 'e9116fc78f43edd606616cd5ad983f1d9f2f6ee69df22829198a2ef1e984da8d',
  ),
  'MediaPipeTasksAudio': (
    url:
        'https://dl.google.com/cpdc/20260911-163655/'
        'MediaPipeTasksAudio-1.0.1.xcframework.zip',
    sha256: 'd458eb5bf2f84281550f0b29b0455f34851d8db2522b91926143c1b625412306',
  ),
};

/// The adapter's sources: the vision tasks, then the text and audio tasks
/// (one translation unit each: Google's frameworks repeat shared headers).
const _adapterSources = [
  'native/ios/face_sdk_bridge.mm',
  'native/ios/text_sdk_bridge.mm',
  'native/ios/audio_sdk_bridge.mm',
];

/// Registers one physical library, with aliases pointing to the same image.
/// Flutter turns mediapipe_ios.dylib into this framework on both iOS SDKs.
void addOfficialIosSdkAssets(
  BuildInput input,
  BuildOutputBuilder output, {
  required File library,
  required Set<String> tasks,
}) {
  // `vision.dylib` is the asset the shared bindings and capability probes use;
  // every name resolves to the one adapter image.
  final names = {...tasks.map((task) => '$task.dylib'), 'vision.dylib'}.toList()
    ..sort();
  for (final name in names) {
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: name,
        file: name == names.first ? library.uri : null,
        linkMode: name == names.first
            ? DynamicLoadingBundled()
            : DynamicLoadingSystem(
                Uri(path: '@rpath/mediapipe_ios.framework/mediapipe_ios'),
              ),
      ),
    );
  }
  output.metadata['official_ios_sdk'] = '1.0.1';
}

/// Downloads Google's libraries and builds only our small Objective-C adapter.
Future<void> buildOfficialIosSdk(
  BuildInput input,
  BuildOutputBuilder output, {
  required Set<String> tasks,
}) async {
  final code = input.config.code;
  if (code.targetOS != OS.iOS ||
      code.targetArchitecture != Architecture.arm64) {
    throw UnsupportedError('official_ios_sdk supports arm64 iOS targets only.');
  }
  final missing = tasks.difference(officialIosTasks);
  if (tasks.isEmpty || missing.isNotEmpty) {
    throw UnsupportedError(
      'official_ios_sdk supports ${officialIosTasks.join(', ')}; '
      'requested ${tasks.join(', ')}.',
    );
  }
  if (!Platform.isMacOS) {
    throw UnsupportedError('The iOS SDK adapter requires Xcode on macOS.');
  }
  final compiler = code.cCompiler;
  if (compiler == null) {
    throw StateError('Xcode C compiler configuration missing.');
  }
  final simulator = code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
  final sdk = simulator ? 'iphonesimulator' : 'iphoneos';
  final slice = simulator ? 'ios-arm64_x86_64-simulator' : 'ios-arm64';
  final cache = Directory.fromUri(
    input.outputDirectoryShared.resolve('official-ios-sdk/'),
  );
  await cache.create(recursive: true);
  final roots = <String, Directory>{};
  // Stream the large graph ZIP from disk; do not hold all architectures in RAM.
  // Always extract from hash-verified archives when rebuilding the adapter.
  for (final entry in officialIosSdkArchives.entries) {
    final archive = File.fromUri(
      cache.uri.resolve('${entry.value.sha256}/sdk.zip'),
    );
    await downloadVerified(entry.value, archive);
    output.dependencies.add(archive.uri);
    final root = Directory.fromUri(archive.parent.uri.resolve('extracted/'));
    await extractOfficialIosSdkSlice(archive, root, slice: slice);
    roots[entry.key] = Directory.fromUri(
      root.uri.resolve('${entry.key}.xcframework/$slice/'),
    );
  }
  final sdkPath = (await _run('xcrun', [
    '--sdk',
    sdk,
    '--show-sdk-path',
  ])).trim();
  final sources = [
    for (final path in _adapterSources) input.packageRoot.resolve(path),
  ];
  final headers = Directory.fromUri(
    input.packageRoot.resolve('third_party/mediapipe/tasks/c/'),
  );
  output.dependencies.addAll(sources);
  output.dependencies.add(
    input.packageRoot.resolve('native/ios/sdk_bridge_support.h'),
  );
  await for (final file in headers.list(recursive: true)) {
    if (file is File && file.path.endsWith('.h')) {
      output.dependencies.add(file.uri);
    }
  }
  final directory = Directory.fromUri(
    input.outputDirectory.resolve('ios-sdk/'),
  );
  await directory.create(recursive: true);
  final library = File.fromUri(directory.uri.resolve('mediapipe_ios.dylib'));
  final temporary = File('${library.path}.tmp');
  await _run(compiler.compiler.toFilePath(), [
    '-x', 'objective-c++', '-std=c++17', '-fobjc-arc', '-O2',
    '-fvisibility=hidden', '-dynamiclib',
    '-target',
    simulator ? 'arm64-apple-ios15.0-simulator' : 'arm64-apple-ios15.0',
    '-isysroot', sdkPath,
    '-I', input.packageRoot.resolve('third_party/').toFilePath(),
    '-F', roots['MediaPipeTasksVision']!.path,
    '-F', roots['MediaPipeTasksCommon']!.path,
    '-F', roots['MediaPipeTasksText']!.path,
    '-F', roots['MediaPipeTasksAudio']!.path,
    for (final source in sources) source.toFilePath(),
    '-framework', 'MediaPipeTasksVision',
    '-framework', 'MediaPipeTasksCommon',
    // Static calculator registrations must survive dead stripping, as in
    // Google's Swift package. Force only SDK archives, not app/plugin code.
    '-Wl,-force_load,${roots['MediaPipeTaskGraphs_library']!.path}/MediaPipeTaskGraphs_library.a',
    '-Wl,-force_load,${roots['MediaPipeTasksCommon']!.path}/MediaPipeTasksCommon.framework/MediaPipeTasksCommon',
    for (final framework in [
      'Foundation',
      'UIKit',
      'Metal',
      'MetalKit',
      'Accelerate',
      'AVFoundation',
      'CoreMedia',
      'AudioToolbox',
      'CoreGraphics',
      'CoreImage',
      'CoreVideo',
      'QuartzCore',
      'OpenGLES',
      'IOSurface',
    ]) ...['-framework', framework],
    '-lc++',
    '-Wl,-install_name,@rpath/mediapipe_ios.framework/mediapipe_ios',
    '-Wl,-headerpad_max_install_names',
    '-Wl,-exported_symbol,_Mp*',
    '-o', temporary.path,
  ]);
  await temporary.rename(library.path);
  final manifest = File.fromUri(directory.uri.resolve('manifest.json'));
  await manifest.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
      'origin': 'google-prebuilt-ios-sdk',
      'version': '1.0.1',
      'sdk': sdk,
      'minimum_os': '15.0',
      'architecture': 'arm64',
      'archives': {
        for (final e in officialIosSdkArchives.entries) e.key: {'url': e.value.url, 'sha256': e.value.sha256},
      },
      'adapter_sha256': {for (final (i, path) in _adapterSources.indexed) path: (await sha256.bind(File.fromUri(sources[i]).openRead()).first).toString()},
      'sha256': (await sha256.bind(library.openRead()).first).toString(),
      'bytes': await library.length(),
      'tasks': tasks.toList()..sort(),
    })}\n',
  );
  addOfficialIosSdkAssets(input, output, library: library, tasks: tasks);
}

/// Extract a requested slice from a verified ZIP without loading other slices.
Future<void> extractOfficialIosSdkSlice(
  File archive,
  Directory destination, {
  required String slice,
}) async {
  final stream = InputFileStream(archive.path);
  try {
    final zip = ZipDecoder().decodeStream(stream);
    for (final entry in zip) {
      final segments = entry.name.split('/');
      if (segments.any((part) => part == '..' || part.contains('\\')) ||
          entry.name.startsWith('/') ||
          entry.isSymbolicLink) {
        throw FormatException('Unsafe SDK archive member: ${entry.name}');
      }
      if (!entry.isFile || !segments.contains(slice)) continue;
      final file = File.fromUri(destination.uri.resolve(entry.name));
      await file.parent.create(recursive: true);
      final output = OutputFileStream(file.path);
      try {
        entry.writeContent(output);
      } finally {
        await output.close();
      }
    }
  } finally {
    await stream.close();
  }
}

Future<String> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw StateError(
      '$executable failed (${result.exitCode}):\n${result.stderr}',
    );
  }
  return result.stdout as String;
}
