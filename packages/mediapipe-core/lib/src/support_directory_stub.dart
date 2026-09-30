import 'dart:io';

/// A pure Dart caller must supply its persistent directory explicitly.
Future<Directory> modelsDirectory() => throw UnsupportedError(
  'A Flutter application is required to locate application support. '
  'Pass directory when using ModelStore from a Dart command-line tool.',
);

/// A caller-supplied directory needs no platform setup.
Future<void> prepareModelsDirectory(Directory directory) async {}
