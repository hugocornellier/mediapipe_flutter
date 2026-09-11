// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:path/path.dart' as path;

import 'repo_finder.dart';

final _log = Logger('DownloadModelCommand');

enum Model { textclassification, textembedding, languagedetection }

class DownloadModelCommand extends Command with RepoFinderMixin {
  @override
  String description =
      'Downloads a given MediaPipe model and places it in '
      'the designated location.';
  @override
  String name = 'model';

  DownloadModelCommand() {
    argParser
      ..addOption(
        'model',
        abbr: 'm',
        allowed: [
          // Values will be added to this as the repository gets more
          // integration tests that require new models.
          Model.textclassification.name,
          Model.textembedding.name,
          Model.languagedetection.name,
        ],
        help:
            'The desired model to download. Use this option if you want the '
            'standard model for a given task. Using this option also removes any '
            'need to use the `destination` option, as a value here implies a '
            'destination. However, you still can specify a destination to '
            'override the default location where the model is placed.\n'
            '\n'
            'Note: Either this or `custommodel` must be used. If both are '
            'supplied, `model` is used.',
      )
      ..addOption(
        'custommodel',
        abbr: 'c',
        help:
            'The desired model to download. Use this option if you want to '
            'specify a specific and nonstandard model. Using this option means '
            'you *must* use the `destination` option.\n'
            '\n'
            'Note: Either this or `model` must be used. If both are supplied, '
            '`model` is used.',
      )
      ..addOption(
        'destination',
        abbr: 'd',
        help:
            'The location to place the downloaded model. This value is required '
            'if you use the `custommodel` option, but optional if you use the '
            '`model` option.',
      );
    addVerboseOption(argParser);
  }

  String getModelSource() => switch (model) {
    Model.textclassification =>
      'https://storage.googleapis.com/mediapipe-models/text_classifier/bert_classifier/float32/1/bert_classifier.tflite',
    Model.textembedding =>
      'https://storage.googleapis.com/mediapipe-models/text_embedder/universal_sentence_encoder/float32/1/universal_sentence_encoder.tflite',
    Model.languagedetection =>
      'https://storage.googleapis.com/mediapipe-models/language_detector/language_detector/float32/1/language_detector.tflite',
  };

  String getModelDestination() => switch (model) {
    Model.textclassification => 'packages/mediapipe-task-text/example/assets/',
    Model.textembedding => 'packages/mediapipe-task-text/example/assets/',
    Model.languagedetection => 'packages/mediapipe-task-text/example/assets/',
  };

  Model get model {
    final value = Model.values.asNameMap()[argResults!['model']];
    if (value == null) {
      throw Exception('Unexpected Model value ${argResults!['model']}');
    }
    return value;
  }

  @override
  Future<void> run() async {
    setUpLogging();
    final io.Directory flutterMediaPipeDirectory = findFlutterMediaPipeRoot();

    late final String modelSource;
    late final String modelDestination;

    if (argResults!['model'] != null) {
      modelSource = getModelSource();
      modelDestination = (_isArgProvided(argResults!['destination']))
          ? argResults!['destination']
          : getModelDestination();
    } else {
      if (argResults!['custommodel'] == null) {
        throw Exception(
          'You must use either the `model` or `custommodel` option.',
        );
      }
      if (argResults!['destination'] == null) {
        throw Exception(
          'If you use the `custommodel` option, then you must supply a '
          '`destination`, as a "standard" destination cannot be used.',
        );
      }
      modelSource = argResults!['custommodel'];
      modelDestination = argResults!['destination'];
    }

    io.File destinationFile = io.File(
      path.joinAll([
        flutterMediaPipeDirectory.absolute.path,
        modelDestination,
        modelSource.split('/').last,
      ]),
    );
    ensureFolders(destinationFile);
    if (argResults!['model'] != null) {
      await downloadVerified((
        url: modelSource,
        sha256: switch (model) {
          Model.textclassification =>
            '9b45012ab143d88d61e10ea501d6c8763f7202b86fa987711519d89bfa2a88b1',
          Model.textembedding =>
            '89ad3c74175dd8caa398cc22b657296d94302d20c525c12b58b29420f7249749',
          Model.languagedetection =>
            '7db4f23dfe1ad8966b050b419a865da451143fd43eb6b606a256aadeeb1e5417',
        },
      ), destinationFile);
    } else {
      await downloadModel(modelSource, destinationFile);
    }
  }

  Future<void> downloadModel(
    String modelSource,
    io.File destinationFile,
  ) async {
    _log.info('Downloading $modelSource');

    // TODO(craiglabenz): Convert to StreamedResponse
    final response = await http.get(Uri.parse(modelSource));

    if (response.statusCode != 200) {
      throw Exception(
        '${response.statusCode} ${response.reasonPhrase} :: '
        '$modelSource',
      );
    }

    if (!(await destinationFile.exists())) {
      _log.fine('Creating file at ${destinationFile.absolute.path}');
      await destinationFile.create();
    }

    _log.fine('Downloaded ${response.contentLength} bytes');
    _log.info('Saving to ${destinationFile.absolute.path}');
    await destinationFile.writeAsBytes(response.bodyBytes);
  }
}

bool _isArgProvided(String? val) => val != null && val != '';
