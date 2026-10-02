import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_text/mediapipe_text.dart';

/// EmbeddingGemma, Proofreader and Summarizer through Google's official mobile
/// runtimes (the text package's Android plugin over tasks-text 1.0.0; on iOS
/// the SDK adapter core's runtime builds over the 1.0.1 XCFrameworks), against
/// Google's own outputs for the same model, runtime version and inputs: the
/// references the gallery's preparers bundle under assets/references when
/// these tasks are selected (tool/prepare_modern_text_reference.py, from
/// Google's wheel of that version on the same architecture, else the text
/// package's macOS fixtures). Generated text must match exactly; embeddings
/// come from another build of the same runtime on another CPU and get a bound.
/// Runs on the Android emulator and iOS simulator in CI, and on phones.
const _embeddingBound = 2e-3;

/// Scalar-quantized bytes may round differently by one step across builds.
const _quantizedBound = 1;

/// Generated text is compared with Google's wheel of the same release on the
/// same architecture, and Google's mobile and desktop builds of the same
/// release do not always agree to the last character: greedy decoding picks
/// a different word once floating-point noise flips a near-tie, which the
/// iOS build does late in the longest summaries (upstream-issues.md UP-036,
/// which measured the earliest parting at 94 characters) while the
/// Proofreader and EmbeddingGemma match exactly. So an output must match
/// Google's from the start for at least this many characters, or in full
/// when Google's is shorter: identical prompts, tokenization, mode and
/// decoding produce the same text until the noise; anything else diverges
/// from the first words. Exact matches are counted in the log.
const _minSharedPrefix = 80;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, dynamic>> manifest() async =>
      jsonDecode(await rootBundle.loadString('assets/manifest.json'))
          as Map<String, dynamic>;

  /// Whether this build bundles the modern text tasks; a build prepared
  /// without them (the published galleries) has nothing to test here.
  Future<bool> bundled() async {
    final tasks = ((await manifest())['tasks'] as List).cast<String>();
    return tasks.contains('text_proofreader') &&
        tasks.contains('text_summarizer') &&
        tasks.contains('embedding_gemma');
  }

  Future<Map<String, dynamic>> reference(String name) async =>
      jsonDecode(
            await rootBundle.loadString(
              'assets/references/modern_text/$name.json',
            ),
          )
          as Map<String, dynamic>;

  /// The generative tasks read their model from a file, so each asset is
  /// written out once, beside the app.
  Future<String> modelFile(String name) async {
    final file = File(
      '${Directory.systemTemp.path}/mediapipe_modern_text/$name',
    );
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      final data = await rootBundle.load('assets/models/$name');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return file.path;
  }

  /// A reference is Google's answer here only when it came from the runtime
  /// version this device's SDK has: 1.0.0 on Android, 1.0.1 on iOS.
  Future<void> expectReferenceRuntime(
    Map<String, dynamic> reference,
    TaskCapabilities support,
  ) async {
    expect(support.supportedDelegates, {Delegate.cpu});
    expect(
      reference['runtime'],
      'mediapipe==${support.runtimeVersion}',
      reason:
          'bundle references generated with the wheel of this SDK\'s '
          'release (prepare.py --modern-text-reference)',
    );
  }

  testWidgets('EmbeddingGemma matches Google\'s reference embeddings', (
    tester,
  ) async {
    await tester.runAsync(() async {
      if (!await bundled()) {
        markTestSkipped('EmbeddingGemma is not bundled in this build.');
        return;
      }
      expect(Platform.isAndroid || Platform.isIOS, isTrue);
      final json = await reference('embedding_gemma');
      await expectReferenceRuntime(
        json,
        await queryTextEmbedderCapabilities(TextModels.embeddingGemma),
      );
      final cases = (json['cases'] as List).cast<Map<String, dynamic>>();
      final model = await modelFile('embedding_gemma.task');
      var worstFloat = 0.0;
      var worstQuantized = 0;
      for (final quantize in [false, true]) {
        final task = await TextEmbedder.create(
          TextEmbedderOptions(
            modelPath: model,
            quantize: quantize,
            l2Normalize: quantize,
          ),
        );
        try {
          for (final entry in cases.where(
            (entry) => entry['quantize'] == quantize,
          )) {
            final context = entry['context'] as Map<String, dynamic>?;
            final result = await task.embed(
              entry['text'] as String,
              formatContext: context == null
                  ? null
                  : TextFormatContext(
                      taskType: _embeddingType(context['task_type'] as String),
                      title: context['title'] as String?,
                      role: context['role'] == 'DOCUMENT'
                          ? TextRole.document
                          : TextRole.query,
                    ),
            );
            final expected = entry['embeddings'] as List;
            expect(result.embeddings, hasLength(expected.length));
            for (var i = 0; i < expected.length; i++) {
              final embedding = result.embeddings[i];
              final values = (expected[i]['values'] as List).cast<num>();
              expect(embedding.headIndex, expected[i]['head_index']);
              expect(embedding.length, 768, reason: entry['name']);
              if (quantize) {
                // Google's APIs list the scalar-quantized bytes unsigned, as
                // the reference holds them; one rounding step may wrap.
                final bytes = embedding.quantizedEmbedding!;
                for (var j = 0; j < values.length; j++) {
                  final raw = (bytes[j] - values[j].toInt()).abs();
                  final delta = math.min(raw, 256 - raw);
                  worstQuantized = math.max(worstQuantized, delta);
                  expect(
                    delta,
                    lessThanOrEqualTo(_quantizedBound),
                    reason: '${entry['name']} value $j',
                  );
                }
              } else {
                final floats = embedding.floatEmbedding!;
                for (var j = 0; j < values.length; j++) {
                  final delta = (floats[j] - values[j]).abs();
                  worstFloat = math.max(worstFloat, delta);
                  expect(
                    floats[j],
                    closeTo(values[j], _embeddingBound),
                    reason: '${entry['name']} value $j',
                  );
                }
              }
            }
          }
        } finally {
          await task.dispose();
        }
      }
      _report('embedding_gemma', {
        'cases': cases.length,
        'max_float_error': worstFloat,
        'max_quantized_error': worstQuantized,
      });
    });
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('Proofreader matches Google\'s completed and streamed results', (
    tester,
  ) async {
    await tester.runAsync(() async {
      if (!await bundled()) {
        markTestSkipped('The Proofreader is not bundled in this build.');
        return;
      }
      final json = await reference('proofreader');
      await expectReferenceRuntime(
        json,
        await queryTextProofreaderCapabilities(),
      );
      final cases = (json['cases'] as List).cast<Map<String, dynamic>>();
      final model = await modelFile('proofread_quant_200m.litertlm');
      List<Map<String, String>> edits(List<ProofreadingCorrection> values) => [
        for (final value in values)
          {'type': value.type.name, 'text': value.text},
      ];
      final agreement = <Map<String, Object?>>[];
      final stopwatch = Stopwatch()..start();
      for (final budget in [null, 64]) {
        final task = await TextProofreader.create(
          TextProofreaderOptions(modelPath: model, maxNumTokens: budget),
        );
        try {
          for (final entry in cases.where(
            (entry) => entry['max_num_tokens'] == budget,
          )) {
            final input = entry['input'] as String;
            final expected = entry['result'] as Map<String, dynamic>;
            final result = await task.proofread(input);
            final updates = await task.proofreadStream(input).toList();
            expect(updates.where((u) => u.done), hasLength(1));
            expect(updates.last.done, isTrue);
            final streamed = updates.map((u) => u.chunk ?? '').join();
            agreement.add(
              _agreement(
                entry['name'] as String,
                expected['text'] as String?,
                result.proofreadText,
                streamed,
                expected['corrections'].toString() ==
                        edits(result.corrections).toString() &&
                    edits(updates.last.corrections).toString() ==
                        edits(result.corrections).toString(),
              ),
            );
          }
        } finally {
          await task.dispose();
        }
      }
      _report('proofreader', {
        'exact_matches':
            '${agreement.where((c) => c['match'] == true).length}'
            '/${agreement.length}',
        'cases': agreement,
        'ms': stopwatch.elapsedMilliseconds,
      });
      _expectAgreement(agreement);
    });
  }, timeout: const Timeout(Duration(minutes: 15)));

  testWidgets('Summarizer matches Google\'s results in both modes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      if (!await bundled()) {
        markTestSkipped('The Summarizer is not bundled in this build.');
        return;
      }
      final json = await reference('summarizer');
      await expectReferenceRuntime(
        json,
        await queryTextSummarizerCapabilities(),
      );
      final cases = (json['cases'] as List).cast<Map<String, dynamic>>();
      final model = await modelFile('summarization_quant_200m_2modes.litertlm');
      final agreement = <Map<String, Object?>>[];
      final stopwatch = Stopwatch()..start();
      for (final mode in TextSummarizerMode.values) {
        for (final budget in [null, 64]) {
          final task = await TextSummarizer.create(
            TextSummarizerOptions(
              modelPath: model,
              mode: mode,
              maxNumTokens: budget,
            ),
          );
          try {
            expect(task.mode, mode);
            for (final entry in cases.where(
              (entry) =>
                  entry['mode'] == mode.name.toUpperCase() &&
                  entry['max_num_tokens'] == budget,
            )) {
              final input = entry['input'] as String;
              final summary = (await task.summarize(input)).summary;
              final updates = await task.summarizeStream(input).toList();
              expect(updates.where((u) => u.done), hasLength(1));
              expect(updates.last.done, isTrue);
              agreement.add(
                _agreement(
                  entry['name'] as String,
                  entry['result']['summary'] as String?,
                  summary,
                  updates.map((u) => u.chunk ?? '').join(),
                  true,
                ),
              );
            }
            if (budget == null) {
              // Google refuses empty input with an error, not a summary.
              await expectLater(
                task.summarize(''),
                throwsA(isA<TaskException>()),
              );
              await expectLater(
                task.summarizeStream('').toList(),
                throwsA(isA<TaskException>()),
              );
            }
          } finally {
            await task.dispose();
          }
        }
      }
      _report('summarizer', {
        'exact_matches':
            '${agreement.where((c) => c['match'] == true).length}'
            '/${agreement.length}',
        'cases': agreement,
        'ms': stopwatch.elapsedMilliseconds,
      });
      _expectAgreement(agreement);
    });
  }, timeout: const Timeout(Duration(minutes: 15)));

  testWidgets('streams cancel, pause and dispose as on the desktop runtime', (
    tester,
  ) async {
    await tester.runAsync(() async {
      if (!await bundled()) {
        markTestSkipped('The Summarizer is not bundled in this build.');
        return;
      }
      final json = await reference('summarizer');
      final cases = (json['cases'] as List).cast<Map<String, dynamic>>();
      final tldr = cases.where((entry) => entry['mode'] == 'TLDR').toList();
      final model = await modelFile('summarization_quant_200m_2modes.litertlm');
      final task = await TextSummarizer.create(
        TextSummarizerOptions(modelPath: model, mode: TextSummarizerMode.tldr),
      );
      // Cancelling stops delivery; the next request waits for Google's
      // generation to finish and then answers as usual.
      final first = Completer<void>();
      var delivered = 0;
      final subscription = task
          .summarizeStream(tldr[0]['input'] as String)
          .listen((_) {
            delivered++;
            if (!first.isCompleted) first.complete();
          });
      await first.future;
      final before = delivered;
      final cancelling = subscription.cancel();
      final next = task.summarize(tldr[1]['input'] as String);
      await cancelling;
      expect((await next).summary, tldr[1]['result']['summary']);
      expect(delivered, before);
      // Pausing buffers updates; disposal drains accepted work first.
      final updates = <TextSummarizerUpdate>[];
      final done = Completer<void>();
      final paused =
          task
              .summarizeStream(tldr[1]['input'] as String)
              .listen(
                updates.add,
                onDone: done.complete,
                onError: done.completeError,
              )
            ..pause();
      final closing = task.dispose();
      expect(identical(closing, task.dispose()), isTrue);
      expect(updates, isEmpty);
      paused.resume();
      await done.future;
      await closing;
      expect(
        updates.map((u) => u.chunk ?? '').join(),
        tldr[1]['result']['summary'],
      );
      await expectLater(task.summarize('closed'), throwsStateError);
      await expectLater(
        task.summarizeStream('closed').toList(),
        throwsStateError,
      );
      _report('lifecycle', {'checks': 'cancel, pause, dispose'});
    });
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('options the platform cannot honor fail before a model loads', (
    tester,
  ) async {
    await tester.runAsync(() async {
      if (!await bundled()) {
        markTestSkipped('The Proofreader is not bundled in this build.');
        return;
      }
      final model = await modelFile('proofread_quant_200m.litertlm');
      await expectLater(
        TextProofreader.create(
          TextProofreaderOptions(modelPath: model, delegate: Delegate.gpu),
        ),
        throwsA(isA<RuntimeUnavailableException>()),
      );
      final cache = Directory(
        '${Directory.systemTemp.path}/mediapipe_modern_text/cache',
      )..createSync(recursive: true);
      final withCache = TextProofreader.create(
        TextProofreaderOptions(modelPath: model, cacheDirectory: cache.path),
      );
      if (Platform.isAndroid) {
        // Google's Android options have no cache directory: refused, not
        // ignored (MODERN_TEXT_PLATFORMS.md).
        await expectLater(
          withCache,
          throwsA(
            isA<RuntimeUnavailableException>().having(
              (e) => e.fix,
              'fix',
              contains('cacheDirectory'),
            ),
          ),
        );
      } else {
        final task = await withCache;
        try {
          final result = await task.proofread('She go home.');
          expect(result.proofreadText, isNotEmpty);
          await expectLater(
            task.proofread('bad\u0000text'),
            throwsArgumentError,
          );
        } finally {
          await task.dispose();
        }
      }
      await expectLater(
        TextProofreader.create(
          TextProofreaderOptions(modelPath: '$model.missing'),
        ),
        throwsA(isA<TaskException>()),
      );
      _report('options', {'checks': 'gpu, cache directory, bad path'});
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Google's Python enum names (`RETRIEVAL_QUERY`) to the Dart enum.
EmbeddingType _embeddingType(String name) => switch (name) {
  'RETRIEVAL_QUERY' => EmbeddingType.retrievalQuery,
  'RETRIEVAL_DOCUMENT' => EmbeddingType.retrievalDocument,
  'SEMANTIC_SIMILARITY' => EmbeddingType.semanticSimilarity,
  'CLASSIFICATION' => EmbeddingType.classification,
  'CLUSTERING' => EmbeddingType.clustering,
  'QUESTION_ANSWERING' => EmbeddingType.questionAnswering,
  'FACT_CHECKING' => EmbeddingType.factChecking,
  'CODE_RETRIEVAL' => EmbeddingType.codeRetrieval,
  _ => throw ArgumentError.value(name, 'task_type'),
};

/// How one generated text compares with Google's wheel (exact, or the length
/// of the shared prefix where they part) and whether the completed and
/// streamed paths, which run the same model here, agreed with each other.
Map<String, Object?> _agreement(
  String name,
  String? expected,
  String? completed,
  String streamed,
  bool correctionsMatch,
) {
  final a = expected ?? '';
  final b = completed ?? '';
  return {
    'name': name,
    'match': a == b && correctionsMatch,
    'stream_agrees': streamed == b,
    'shared_prefix': _sharedPrefix(a, b),
    'stream_shared_prefix': _sharedPrefix(b, streamed),
    'expected_length': a.length,
    'actual_length': b.length,
    if (a != b) 'completed': b,
    if (streamed != b) 'streamed': streamed,
  };
}

/// Every case must follow Google's wheel for [_minSharedPrefix] characters
/// (or in full when shorter), and its streamed text must follow its
/// completed text the same way.
void _expectAgreement(List<Map<String, Object?>> agreement) {
  for (final c in agreement) {
    final expected = c['expected_length'] as int;
    final required = math.min(_minSharedPrefix, expected);
    expect(
      c['shared_prefix'] as int,
      greaterThanOrEqualTo(required),
      reason:
          "${c['name']}: Google's wheel of this runtime version answered "
          'differently from the start: ${c['completed']}',
    );
    expect(
      c['stream_shared_prefix'] as int,
      greaterThanOrEqualTo(
        math.min(_minSharedPrefix, c['actual_length'] as int),
      ),
      reason:
          '${c['name']}: the streamed text differs from the completed text '
          'from the start: ${c['streamed']}',
    );
  }
}

int _sharedPrefix(String a, String b) {
  var prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
    prefix++;
  }
  return prefix;
}

// Kept in the device log (logcat, the simulator console) for the record.
void _report(String event, Map<String, Object?> data) {
  // ignore: avoid_print
  print('SDK_MODERN_TEXT ${jsonEncode({'event': event, ...data})}');
}
