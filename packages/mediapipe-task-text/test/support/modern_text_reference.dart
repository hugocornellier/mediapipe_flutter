/// Google's outputs the EmbeddingGemma, Proofreader and Summarizer tests
/// compare with: the checked-in macOS arm64 fixtures, or the same-host
/// references `tool/prepare_modern_text_reference.py` generated into
/// `MEDIAPIPE_MODERN_TEXT_REFERENCE_DIR` (`<task>.json`), which the Linux and
/// Windows CI runners do with the wheel their runtime comes from.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
/// Google's answer for this host when it came from the release line its
/// runtime reports: a reference from Google's 1.1.0 release candidate wheel
/// counts for the 1.1.1 libraries, and the comparisons check each answer.
Future<void> expectReferenceRuntime(
  Map<String, dynamic> reference,
  Future<TaskCapabilities> Function() capabilities,
) async {
  final support = await capabilities();
  final line = support.runtimeVersion.split('.').take(2).join('.');
  expect(
    reference['runtime'],
    startsWith('mediapipe==$line.'),
    reason:
        'The reference was generated with another MediaPipe version than '
        "this host's pinned runtime. Generate same-host references with "
        'tool/prepare_modern_text_reference.py and point '
        'MEDIAPIPE_MODERN_TEXT_REFERENCE_DIR at them.',
  );
}

/// Requires [actual] to follow Google's [expected] from the start for 80
/// characters, or in full when Google's is shorter. Google's generated text
/// differs between builds and machines late in long answers
/// (upstream-issues.md UP-036): greedy decoding picks another word once
/// floating-point noise flips a near tie, so Google's per-family libraries
/// and its reference wheel, different builds, part after 100 to 170
/// characters of a summary on most hosts, though not on an M4 Mac. The text
/// also depends on the requests before it on the same task: on Google's
/// x86_64 1.0.0 builds the first streamed request of a fresh Proofreader was
/// worded differently from the reference, recorded after a completed one. The
/// reference tests replay the generator's request order and compare exactly;
/// the stream and lifecycle checks do not, so they ask this much, and the
/// Summarizer's count their exact matches.
void expectFollows(String? actual, String? expected, {String? reason}) {
  final a = expected ?? '';
  final b = actual ?? '';
  var prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
    prefix++;
  }
  expect(
    prefix,
    greaterThanOrEqualTo(math.min(80, a.length)),
    reason: '${reason ?? ''}: Google answered "$a", the task answered "$b"',
  );
}
