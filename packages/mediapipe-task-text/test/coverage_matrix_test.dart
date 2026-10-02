import 'dart:convert';
import 'dart:io';

import 'package:mediapipe_text/mediapipe_text.dart';
import 'package:mediapipe_text/platform_interface.dart';
import 'package:test/test.dart';

// The CI coverage gate (tool/coverage/gate.py) requires a passing row for
// every 'required' and 'device' cell of tool/coverage/matrix.json. This keeps
// that matrix and the package's capability claims from drifting: a required
// cell must be a claimed capability, and an 'unsupported' cell must not be.
// Claims are read with the platform plugin registered, as in an app.
const _platforms = {
  'web': TaskPlatform(operatingSystem: 'web', architecture: 'unknown'),
  'android': TaskPlatform(operatingSystem: 'android', architecture: 'arm64'),
  'ios': TaskPlatform(
    operatingSystem: 'ios',
    architecture: 'arm64',
    version: '15.0',
  ),
  'macos': TaskPlatform(
    operatingSystem: 'macos',
    architecture: 'arm64',
    version: '14.0',
  ),
  'linux': TaskPlatform(operatingSystem: 'linux', architecture: 'x64'),
  'windows': TaskPlatform(operatingSystem: 'windows', architecture: 'x64'),
};

final _claims = <String, TaskCapabilities Function(TaskPlatform)>{
  'text_classifier': textClassifierCapabilitiesForPlatform,
  'language_detector': languageDetectorCapabilitiesForPlatform,
  'text_embedder': textEmbedderCapabilitiesForPlatform,
  'embedding_gemma': (p) =>
      textEmbedderCapabilitiesForPlatform(p, model: TextModels.embeddingGemma),
  'text_proofreader': textProofreaderCapabilitiesForPlatform,
  'text_summarizer': textSummarizerCapabilitiesForPlatform,
};

Never _unused(String task, Map<String, Object?> options) =>
    throw UnimplementedError();

void main() {
  setUpAll(() => textTaskBackendFactory = _unused);
  tearDownAll(() => textTaskBackendFactory = null);

  test('coverage matrix agrees with the text capability claims', () {
    final matrix =
        jsonDecode(
              File('../../tool/coverage/matrix.json').readAsStringSync(),
            )['cells']
            as Map<String, Object?>;
    final problems = <String>[];
    for (final MapEntry(key: task, value: claim) in _claims.entries) {
      final platforms = matrix[task]! as Map<String, Object?>;
      for (final MapEntry(key: name, value: platform) in _platforms.entries) {
        final claimed = claim(platform).supportedDelegates;
        final cells = platforms[name]! as Map<String, Object?>;
        for (final delegate in Delegate.values) {
          final status = cells[delegate.name]! as String;
          final cell = '$task / $name / ${delegate.name}';
          if ((status == 'required' || status == 'device') &&
              !claimed.contains(delegate)) {
            problems.add('$cell is $status but not claimed');
          }
          if (status.startsWith('unsupported') && claimed.contains(delegate)) {
            problems.add('$cell is claimed but marked "$status"');
          }
        }
      }
    }
    expect(problems, isEmpty);
  });
}
