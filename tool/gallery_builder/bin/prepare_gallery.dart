import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

final class Model {
  const Model(this.fileName, this.url, this.sha256);

  final String fileName;
  final String url;
  final String sha256;
}

const _models = <String, Model>{
  'audio_classifier': Model(
    'yamnet.tflite',
    'https://storage.googleapis.com/mediapipe-models/audio_classifier/yamnet/float32/1/yamnet.tflite',
    '4d8b4a53282dc83ef04e3e7dbc4fbc98082e34e44ed798e16c3a0cdd4c584faf',
  ),
  'face_detector': Model(
    'blaze_face_short_range.tflite',
    'https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite',
    'b4578f35940bf5a1a655214a1cce5cab13eba73c1297cd78e1a04c2380b0152f',
  ),
  'face_landmarker': Model(
    'face_landmarker.task',
    'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task',
    '64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff',
  ),
  'gesture_recognizer': Model(
    'gesture_recognizer.task',
    'https://storage.googleapis.com/mediapipe-models/gesture_recognizer/gesture_recognizer/float16/1/gesture_recognizer.task',
    '97952348cf6a6a4915c2ea1496b4b37ebabc50cbbf80571435643c455f2b0482',
  ),
  'hand_landmarker': Model(
    'hand_landmarker.task',
    'https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task',
    'fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1',
  ),
  'holistic_landmarker': Model(
    'holistic_landmarker.task',
    'https://storage.googleapis.com/mediapipe-models/holistic_landmarker/holistic_landmarker/float16/1/holistic_landmarker.task',
    'e2dab61191e2dcd0a15f943d8e3ed1dce13c82dfa597b9dd39f562975a50c3f8',
  ),
  'image_classifier': Model(
    'efficientnet_lite0.tflite',
    'https://storage.googleapis.com/mediapipe-models/image_classifier/efficientnet_lite0/float32/1/efficientnet_lite0.tflite',
    '6c7ab0a6e5dcbf38a8c33b960996a55a3b4300b36a018c4545801de3a3c8bde0',
  ),
  'image_embedder': Model(
    'mobilenet_v3_small.tflite',
    'https://storage.googleapis.com/mediapipe-models/image_embedder/mobilenet_v3_small/float32/1/mobilenet_v3_small.tflite',
    'bbbb4c51a55a53905af1daec995ca1aae355046f8839bb8c9f5ce9271394bc40',
  ),
  'image_segmenter': Model(
    'deeplab_v3.tflite',
    'https://storage.googleapis.com/mediapipe-models/image_segmenter/deeplab_v3/float32/1/deeplab_v3.tflite',
    'ff36e24d40547fe9e645e2f4e8745d1876d6e38b332d39a82f0bf0f5d1d561b3',
  ),
  'interactive_segmenter': Model(
    'interactive_segmentation.task',
    'https://storage.googleapis.com/mediapipe-models/interactive_segmenter_v2/magic_touch/int8/1/interactive_segmentation.task',
    '38431bc66b883404e8397f74c3579404315b9b52b04a46c6346fe906a7309b03',
  ),
  'language_detector': Model(
    'language_detector.tflite',
    'https://storage.googleapis.com/mediapipe-models/language_detector/language_detector/float32/1/language_detector.tflite',
    '7db4f23dfe1ad8966b050b419a865da451143fd43eb6b606a256aadeeb1e5417',
  ),
  'object_detector': Model(
    'efficientdet_lite0.tflite',
    'https://storage.googleapis.com/mediapipe-models/object_detector/efficientdet_lite0/float32/1/efficientdet_lite0.tflite',
    '40338edf5ec70d43e318b0a716a84d4564cd1802759a7a07170c7e43796dbf58',
  ),
  'pose_landmarker': Model(
    'pose_landmarker_lite.task',
    'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task',
    '59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a',
  ),
  'text_classifier': Model(
    'bert_classifier.tflite',
    'https://storage.googleapis.com/mediapipe-models/text_classifier/bert_classifier/float32/1/bert_classifier.tflite',
    '9b45012ab143d88d61e10ea501d6c8763f7202b86fa987711519d89bfa2a88b1',
  ),
  'text_embedder': Model(
    'universal_sentence_encoder.tflite',
    'https://storage.googleapis.com/mediapipe-models/text_embedder/universal_sentence_encoder/float32/1/universal_sentence_encoder.tflite',
    '89ad3c74175dd8caa398cc22b657296d94302d20c525c12b58b29420f7249749',
  ),
};

const _nonVisionTasks = {
  'audio_classifier',
  'language_detector',
  'text_classifier',
  'text_embedder',
};

const _samples = <String, String>{
  'packages/mediapipe-task-vision/test/fixtures/face_detection/landmark-ex1.jpg':
      'portrait.jpg',
  'packages/mediapipe-task-vision/test/fixtures/face_detection/group-shot-bounding-box-ex1.jpeg':
      'group.jpeg',
  'packages/mediapipe-task-vision/test/fixtures/landmark_tasks/right_hands.jpg':
      'hands.jpg',
  'packages/mediapipe-task-vision/test/fixtures/landmark_tasks/pose.jpg':
      'pose.jpg',
  'packages/mediapipe-task-vision/test/fixtures/landmark_tasks/thumb_up.jpg':
      'thumb_up.jpg',
  'packages/mediapipe-task-vision/test/fixtures/interactive_segmentation/cats_and_dogs.jpg':
      'animals.jpg',
  'packages/mediapipe-task-audio/test/fixtures/speech_16000_hz_mono.wav':
      'speech_16000_hz_mono.wav',
  'packages/mediapipe-task-audio/test/fixtures/speech_48000_hz_mono.wav':
      'speech_48000_hz_mono.wav',
  'packages/mediapipe-task-audio/test/fixtures/two_heads_16000_hz_mono.wav':
      'two_heads_16000_hz_mono.wav',
  'gallery/samples/dog.jpg': 'dog.jpg',
  'gallery/samples/cat.png': 'cat.png',
  'gallery/samples/elephant.png': 'elephant.png',
};

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
      ? _models.keys.toSet()
      : requested.split(',').map((task) => task.trim()).toSet();
  final unknown = tasks.difference(_models.keys.toSet());
  if (unknown.isNotEmpty) {
    stderr.writeln(
      'Unavailable tasks for $target: ${unknown.toList()..sort()}',
    );
    exitCode = 64;
    return;
  }

  final repo = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '../../..'),
  );
  final gallery = p.join(repo, 'gallery');
  final modelsDirectory = Directory(p.join(gallery, 'assets/models'));
  final samplesDirectory = Directory(p.join(gallery, 'assets/samples'));
  await _replaceDirectory(modelsDirectory);
  await _replaceDirectory(samplesDirectory);

  final client = http.Client();
  try {
    for (final task in tasks.toList()..sort()) {
      final model = _models[task]!;
      stdout.writeln('Preparing $task (${model.fileName})...');
      await _downloadVerified(
        model,
        File(p.join(modelsDirectory.path, model.fileName)),
        client,
      );
    }
  } finally {
    client.close();
  }

  final sampleNames = <String>[];
  for (final entry in _samples.entries) {
    if (!tasks.contains('audio_classifier') && entry.value.endsWith('.wav')) {
      continue;
    }
    if (!tasks.contains('image_embedder') &&
        const {'dog.jpg', 'cat.png', 'elephant.png'}.contains(entry.value)) {
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

  final sortedTasks = tasks.toList()..sort();
  final modelNames = <String, String>{
    for (final task in sortedTasks) task: _models[task]!.fileName,
  };
  final manifest = <String, Object?>{
    'target': target,
    'tasks': sortedTasks,
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
  ).writeAsString(_pubspec(target, sortedTasks, modelNames, sampleNames));

  stdout.writeln('$target: ${sortedTasks.length} task(s) bundled');
  for (final task in sortedTasks) {
    stdout.writeln('  + $task');
  }
}

Future<void> _replaceDirectory(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
  await directory.create(recursive: true);
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
    final actual = (await sha256.bind(temporary.openRead()).first).toString();
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
  final nativeTasks = tasks.where((task) => !_nonVisionTasks.contains(task));
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
