import 'dart:io';

Future<void> main() async {
  // ffigen 21 does not visit C++ LinkageSpec cursors. Remove only the enclosing
  // extern-C blocks in temporary copies; every ABI declaration stays identical.
  await for (final entry in Directory(
    'third_party/mediapipe',
  ).list(recursive: true)) {
    if (entry is! File || !entry.path.endsWith('.h')) continue;
    final destination = File(
      entry.path.replaceFirst('third_party/', 'build/ffigen/'),
    );
    await destination.parent.create(recursive: true);
    final source = await entry.readAsString();
    await destination.writeAsString(
      source
          .replaceAll('extern "C" {', '')
          .replaceAll(
            RegExp(r'^\}  // extern (?:"C"|C).*$', multiLine: true),
            '',
          ),
    );
  }
  final sdk = await Process.run('xcrun', ['--show-sdk-path']);
  if (sdk.exitCode != 0) {
    throw StateError('Xcode is required to regenerate the macOS bindings.');
  }
  final path = (sdk.stdout as String).trim();
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    'ffigen',
    '--config=ffigen.yaml',
    '--compiler-opts',
    '-isystem "$path/usr/include/c++/v1"',
  ], mode: ProcessStartMode.inheritStdio);
  exitCode = await process.exitCode;
}
