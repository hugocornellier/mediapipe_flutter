import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:gallery_builder/models.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('target', mandatory: true)
    ..addOption('tasks', help: 'Comma-separated task subset.');
  late final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final target = options.option('target')!;
  if (target != 'android/arm64' && target != 'android/x64') {
    stderr.writeln(
      'This Dart preparer currently supports android/arm64 and android/x64.',
    );
    exitCode = 64;
    return;
  }
  final requested = options.option('tasks');
  final tasks = requested == null
      ? models.keys.toSet()
      : requested.split(',').map((task) => task.trim()).toSet();
  final unknown = tasks.difference(models.keys.toSet());
  if (unknown.isNotEmpty) {
    stderr.writeln(
      'Unavailable tasks for $target: ${unknown.toList()..sort()}',
    );
    exitCode = 64;
    return;
  }

  try {
    await _prepare(target, tasks.toList()..sort());
  } on Object catch (error) {
    // Nothing needs cleaning up: a rerun keeps the models already verified
    // and fetches the rest.
    stderr.writeln('\nPreparation failed: $error');
    stderr.writeln('Nothing was built. Check the network and run it again.');
    exitCode = 1;
  }
}

Future<void> _prepare(String target, List<String> tasks) async {
  final repo = _repositoryRoot();
  final gallery = p.join(repo, 'gallery');
  final modelsDirectory = Directory(p.join(gallery, 'assets/models'));
  final samplesDirectory = Directory(p.join(gallery, 'assets/samples'));
  await modelsDirectory.create(recursive: true);

  final client = http.Client();
  try {
    for (final task in tasks) {
      final model = models[task]!;
      stdout.writeln('Preparing $task (${model.fileName})...');
      await _prepareModel(
        model,
        File(p.join(modelsDirectory.path, model.fileName)),
        client,
      );
    }
  } finally {
    client.close();
  }
  // Models another target or an earlier task list left behind.
  final bundled = {for (final task in tasks) models[task]!.fileName};
  await for (final entity in modelsDirectory.list()) {
    if (entity is File && !bundled.contains(p.basename(entity.path))) {
      await entity.delete();
    }
  }

  await _replaceDirectory(samplesDirectory);
  final sampleNames = <String>[];
  for (final entry in samples.entries) {
    if (!tasks.contains('audio_classifier') && entry.value.endsWith('.wav')) {
      continue;
    }
    if (!tasks.contains('image_embedder') &&
        embedderSamples.contains(entry.value)) {
      continue;
    }
    final source = File(p.join(repo, entry.key));
    if (!await source.exists()) {
      throw StateError('Required sample is missing: ${source.path}');
    }
    await source.copy(p.join(samplesDirectory.path, entry.value));
    sampleNames.add(entry.value);
  }
  sampleNames.sort();

  final modelNames = <String, String>{
    for (final task in tasks) task: models[task]!.fileName,
  };
  final manifest = <String, Object?>{
    'target': target,
    'tasks': tasks,
    'models': modelNames,
    'samples': sampleNames,
    'official_macos_landmark_tasks': <String>[],
    'official_ios_sdk': null,
    'official_android_sdk': '1.0.0',
    'official_web_sdk': null,
  };
  await File(
    p.join(gallery, 'assets/manifest.json'),
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
  await File(
    p.join(gallery, 'pubspec.yaml'),
  ).writeAsString(_pubspec(target, tasks, modelNames, sampleNames));

  stdout.writeln('$target: ${tasks.length} task(s) bundled');
  for (final task in tasks) {
    stdout.writeln('  + $task');
  }
  stdout.writeln(
    '\nNext: cd gallery, then flutter run -d <device-id> --release',
  );
}

/// The checkout this script belongs to, found by the marker file at its
/// root, so the script works from any directory.
String _repositoryRoot() {
  final script = Platform.script;
  final starts = [
    if (script.scheme == 'file') p.dirname(script.toFilePath()),
    Directory.current.path,
  ];
  for (final start in starts) {
    var directory = p.normalize(p.absolute(start));
    while (true) {
      if (File(p.join(directory, '.mediapipe_flutter-root')).existsSync()) {
        return directory;
      }
      final parent = p.dirname(directory);
      if (parent == directory) break;
      directory = parent;
    }
  }
  throw StateError(
    'Run this from a mediapipe_flutter checkout; '
    'no .mediapipe_flutter-root above ${starts.join(' or ')}.',
  );
}

Future<void> _replaceDirectory(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
  await directory.create(recursive: true);
}

Future<String> _sha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Keeps a model already verified by an earlier run, and otherwise downloads
/// it, retrying twice: a phone build should not fail on one dropped
/// connection.
Future<void> _prepareModel(
  Model model,
  File destination,
  http.Client client,
) async {
  if (await destination.exists() &&
      await _sha256(destination) == model.sha256) {
    stdout.writeln('  already downloaded and verified');
    return;
  }
  for (var attempt = 1; ; attempt++) {
    try {
      await _downloadVerified(model, destination, client);
      return;
    } on Object catch (error) {
      if (attempt == 3) {
        throw StateError('${model.fileName}: $error');
      }
      stderr.writeln('  attempt $attempt failed ($error); retrying');
      await Future<void>.delayed(Duration(seconds: 2 * attempt));
    }
  }
}

Future<void> _downloadVerified(
  Model model,
  File destination,
  http.Client client,
) async {
  final source = Platform.environment['MEDIAPIPE_ASSET_SOURCE'];
  final uri = source == null || source.isEmpty
      ? Uri.parse(model.url)
      : source.startsWith('http://') || source.startsWith('https://')
      ? Uri.parse(
          '${source.endsWith('/') ? source : '$source/'}${model.sha256}',
        )
      : File(p.join(source, model.sha256)).uri;
  final temporary = File('${destination.path}.download');
  try {
    if (uri.scheme == 'file') {
      await File.fromUri(uri).copy(temporary.path);
    } else {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final sink = temporary.openWrite();
      try {
        await sink.addStream(
          response.stream.timeout(const Duration(seconds: 60)),
        );
      } finally {
        await sink.close();
      }
    }
    final actual = await _sha256(temporary);
    if (actual != model.sha256) {
      throw StateError(
        'SHA-256 mismatch for ${model.fileName}: expected ${model.sha256}, got $actual',
      );
    }
    await temporary.rename(destination.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

String _pubspec(
  String target,
  List<String> tasks,
  Map<String, String> models,
  List<String> samples,
) {
  final assets = <String>{...models.values}.toList()..sort();
  final entries = [
    for (final name in assets) '    - assets/models/$name',
    for (final name in samples) '    - assets/samples/$name',
  ].join('\n');
  final nativeTasks = tasks.where((task) => !nonVisionTasks.contains(task));
  return '''# Generated by tool/gallery_builder for $target. Do not edit by hand:
# the task list is per-target and the build hook rejects unavailable tasks.
name: mediapipe_gallery
description: A portal to every MediaPipe task this repository supports.
publish_to: none
version: 0.1.0+1

environment:
  sdk: ^3.12.0

dependencies:
  flutter:
    sdk: flutter
  mediapipe_vision:
    path: ../packages/mediapipe-task-vision
  mediapipe_core:
    path: ../packages/mediapipe-core
  mediapipe_text:
    path: ../packages/mediapipe-task-text
  mediapipe_audio:
    path: ../packages/mediapipe-task-audio
  web: ^1.1.1
  crypto: ^3.0.6
  file_selector: ^1.0.3
  image_picker: ^1.2.2
  record: ^7.1.1
  url_launcher: ^6.3.2
  lucide_icons_flutter: ^3.1.20
  camera: ^0.12.1

dev_dependencies:
  camera_platform_interface: ^2.13.1
  flutter_lints: ^6.0.0
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter

hooks:
  user_defines:
    mediapipe_vision:
      tasks: [${nativeTasks.join(', ')}]

flutter:
  uses-material-design: true
  fonts:
    - family: Arimo
      fonts:
        - asset: fonts/Arimo-400.ttf
        - asset: fonts/Arimo-600.ttf
          weight: 600
        - asset: fonts/Arimo-700.ttf
          weight: 700
  assets:
    - assets/manifest.json
$entries
''';
}
