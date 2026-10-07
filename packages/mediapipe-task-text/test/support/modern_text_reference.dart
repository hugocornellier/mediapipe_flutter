/// Google's outputs the EmbeddingGemma, Proofreader and Summarizer tests
/// compare with: the checked-in macOS arm64 fixtures, or the same-host
/// references `tool/prepare_modern_text_reference.py` generated into
/// `MEDIAPIPE_MODERN_TEXT_REFERENCE_DIR` (`<task>.json`), which the Linux and
/// Windows CI runners do with the wheel their runtime comes from.
library;

import 'dart:convert';
import 'dart:io';

import 'package:mediapipe_text/mediapipe_text.dart';
import 'package:test/test.dart';

/// The reference for [task] (`embedding_gemma`, `proofreader` or
/// `summarizer`).
Map<String, dynamic> loadReference(String task) {
  final directory = Platform.environment['MEDIAPIPE_MODERN_TEXT_REFERENCE_DIR'];
  final file = directory == null
      ? File('test/fixtures/$task/official_reference.json')
      : File('$directory/$task.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Google's releases generate different text, so a reference is only
/// Google's answer for this host when it came from the release its runtime
/// reports: a reference from Google's 1.1.0 release candidate wheel counts
/// for the 1.1.0 libraries.
Future<void> expectReferenceRuntime(
  Map<String, dynamic> reference,
  Future<TaskCapabilities> Function() capabilities,
) async {
  final support = await capabilities();
  expect(
    reference['runtime'],
    startsWith('mediapipe==${support.runtimeVersion}'),
    reason:
        'The reference was generated with another MediaPipe version than '
        "this host's pinned runtime. Generate same-host references with "
        'tool/prepare_modern_text_reference.py and point '
        'MEDIAPIPE_MODERN_TEXT_REFERENCE_DIR at them.',
  );
}
