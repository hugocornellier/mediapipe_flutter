/// Checks each family's public API: identical on native and web, within the
/// conventions, free of collisions with Dart's and Flutter's names, and equal
/// to its reviewed snapshot. `--update` rewrites the baseline and snapshots.
library;

import 'dart:io';

import 'package:api_parity/api_dump.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// Each family's package directory and app-facing library.
const families = {
  'core': (
    'packages/mediapipe-core',
    'package:mediapipe_core/mediapipe_core.dart',
  ),
  'vision': (
    'packages/mediapipe-task-vision',
    'package:mediapipe_vision/mediapipe_vision.dart',
  ),
  'text': (
    'packages/mediapipe-task-text',
    'package:mediapipe_text/mediapipe_text.dart',
  ),
  'audio': (
    'packages/mediapipe-task-audio',
    'package:mediapipe_audio/mediapipe_audio.dart',
  ),
  'retrieval': (
    'packages/mediapipe-task-retrieval',
    'package:mediapipe_retrieval/mediapipe_retrieval.dart',
  ),
};

/// Libraries an app imports beside a family; a public name they also export
/// could not be used from such an app without a prefix.
const collisionLibraries = [
  'dart:core',
  'dart:async',
  'dart:collection',
  'dart:typed_data',
  'dart:math',
  'package:flutter/foundation.dart',
  'package:flutter/services.dart',
  'package:flutter/widgets.dart',
  'package:flutter/material.dart',
  'package:flutter/cupertino.dart',
];

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('update', help: 'Rewrite the baseline and the snapshots.')
    ..addOption('root', help: 'Repository root; defaults to this checkout.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(arguments);
  if (args.flag('help')) {
    stdout.writeln('dart run bin/api_parity.dart [--update] [--root DIR]\n');
    stdout.writeln(parser.usage);
    return;
  }
  final root = p.normalize(
    p.absolute(
      args.option('root') ??
          p.join(p.dirname(Platform.script.toFilePath()), '..', '..', '..'),
    ),
  );
  final tool = p.join(root, 'tool', 'api_parity');
  final findings = <String>[];
  final snapshots = <String, String>{};

  final reserved = await _reservedNames(root);
  for (final MapEntry(key: family, value: (directory, uri))
      in families.entries) {
    final packageRoot = p.join(root, directory);
    stdout.writeln('Analyzing $uri');
    final native = await dumpLibrary(
      packageRoot: packageRoot,
      uri: uri,
      declaredVariables: nativeLibraries,
    );
    final web = await dumpLibrary(
      packageRoot: packageRoot,
      uri: uri,
      declaredVariables: webLibraries,
    );
    final nativeLines = native.lines.toSet();
    final webLines = web.lines.toSet();
    for (final line in native.lines) {
      if (!webLines.contains(line)) {
        findings.add('[$family] native only: ${line.trim()}');
      }
    }
    for (final line in web.lines) {
      if (!nativeLines.contains(line)) {
        findings.add('[$family] web only: ${line.trim()}');
      }
    }
    for (final finding in {...native.platformTypes, ...web.platformTypes}) {
      findings.add('[$family] platform type: $finding');
    }
    for (final finding in {...native.conventions, ...web.conventions}) {
      findings.add('[$family] convention: $finding');
    }
    for (final name in {...native.names, ...web.names}.toList()..sort()) {
      if (reserved[name] case final library?) {
        findings.add('[$family] collision: $name is also in $library');
      }
    }
    snapshots['$family.txt'] = '${native.lines.join('\n')}\n';
    snapshots['$family.web.txt'] =
        nativeLines.containsAll(webLines) && webLines.containsAll(nativeLines)
        ? ''
        : '${web.lines.join('\n')}\n';
  }

  final baselineFile = File(p.join(tool, 'baseline.txt'));
  final snapshotDirectory = Directory(p.join(tool, 'snapshots'));
  if (args.flag('update')) {
    baselineFile.writeAsStringSync(_baseline(findings));
    snapshotDirectory.createSync();
    for (final MapEntry(key: name, value: content) in snapshots.entries) {
      final file = File(p.join(snapshotDirectory.path, name));
      if (content.isEmpty) {
        if (file.existsSync()) file.deleteSync();
      } else {
        file.writeAsStringSync(content);
      }
    }
    stdout.writeln(
      'Wrote ${findings.length} baseline entries and '
      '${snapshots.values.where((s) => s.isNotEmpty).length} snapshots.',
    );
    return;
  }

  final baseline = baselineFile.existsSync()
      ? baselineFile
            .readAsLinesSync()
            .where((line) => line.isNotEmpty && !line.startsWith('#'))
            .toSet()
      : <String>{};
  final failures = <String>[];
  for (final finding in findings) {
    if (!baseline.contains(finding)) failures.add('new: $finding');
  }
  for (final entry in baseline) {
    if (!findings.contains(entry)) failures.add('fixed, prune: $entry');
  }
  for (final MapEntry(key: name, value: content) in snapshots.entries) {
    final file = File(p.join(snapshotDirectory.path, name));
    final recorded = file.existsSync() ? file.readAsStringSync() : '';
    if (recorded != content) failures.add('snapshot differs: $name');
  }
  if (failures.isEmpty) {
    stdout.writeln(
      'API parity: ${findings.length} known findings, snapshots unchanged.',
    );
    return;
  }
  stderr.writeln('API parity check failed:');
  for (final failure in failures) {
    stderr.writeln('  $failure');
  }
  stderr.writeln(
    'Review the change, then run `dart run tool/api_parity/bin/api_parity.dart '
    '--update` and commit baseline.txt and snapshots/.',
  );
  exitCode = 1;
}

String _baseline(List<String> findings) {
  final buffer = StringBuffer()
    ..writeln(
      '# Findings the public API still has: differences between the native and '
      'web\n# APIs, platform types in signatures, convention gaps and name '
      'collisions.\n# `dart run tool/api_parity/bin/api_parity.dart --update` '
      'rewrites it; it may only shrink.',
    );
  for (final finding in findings) {
    buffer.writeln(finding);
  }
  return buffer.toString();
}

/// Every public name the [collisionLibraries] export, with the first library
/// that exports it. Resolved from the vision package, which depends on Flutter.
Future<Map<String, String>> _reservedNames(String root) async {
  final reserved = <String, String>{};
  for (final uri in collisionLibraries) {
    final library = await resolveLibrary(
      packageRoot: p.join(root, families['vision']!.$1),
      uri: uri,
      declaredVariables: nativeLibraries,
    );
    for (final name in library.exportNamespace.definedNames2.keys) {
      reserved.putIfAbsent(name, () => uri);
    }
  }
  return reserved;
}
