@TestOn('vm')
@Tags(['native-assets'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:mediapipe_decision/mediapipe_decision.dart';
import 'package:test/test.dart';

/// Google's Laya model; `make models_decision` downloads it.
final _laya =
    Platform.environment['MEDIAPIPE_DECISION_MODEL'] ?? 'models/laya_s256.task';

/// Google's text and vision EmbeddingGemma 2 (388 MB), when set: the
/// bi-encoder Google's per-family library runs, which fails with the
/// text-only one (upstream-issues.md UP-053). The same cases check it
/// against the wheel's answers for it, locally; CI downloads Laya alone.
final _gemma = Platform.environment['MEDIAPIPE_DECISION_EG2_MODEL'];

final _host =
    '${Platform.operatingSystem}/${Abi.current().toString().split('_').last}';

String? _missing(String model, String name) =>
    File(model).existsSync() ? null : 'No $name model at $model.';

void main() {
  final laya = _missing(_laya, 'Laya');
  _suite('Laya', _laya, 'laya_s256_reference.json', laya);
  if (_gemma case final gemma?) {
    _suite(
      'EmbeddingGemma 2',
      gemma,
      'embedding_gemma_2_text_vision_reference.json',
      _missing(gemma, 'EmbeddingGemma 2'),
    );
  }

  test('a disposed task refuses requests', skip: laya, () async {
    final other = await DecisionMaker.create(
      DecisionMakerOptions(modelPath: _laya),
    );
    await other.dispose();
    await other.dispose();
    expect(
      () => other.evaluateBoolean('text', BooleanQuestion('A condition.')),
      throwsStateError,
    );
  });

  // Google's per-family library fails every evaluation with the text-only
  // EmbeddingGemma 2 (UP-053): a pinned model is refused before any download,
  // and the library's own failure, for a model given by path, names the fix.
  final perFamily = !embeddingGemma2TextTargets.containsKey(_host);
  test('the text-only EmbeddingGemma 2 is refused before any download', () {
    expect(
      DecisionMaker.create(
        DecisionMakerOptions(model: DecisionModels.embeddingGemma2Text),
      ),
      throwsA(
        isA<RuntimeUnavailableException>().having(
          (error) => error.fix,
          'fix',
          allOf(contains('UP-053'), contains('embeddingGemma2TextVision')),
        ),
      ),
    );
  }, skip: perFamily ? null : 'the wheel library runs the model');

  final textOnly = Platform.environment['MEDIAPIPE_DECISION_EG2_TEXT_MODEL'];
  test(
    'the library\'s failure with the text-only model names the fix',
    () async {
      final task = await DecisionMaker.create(
        DecisionMakerOptions(modelPath: textOnly!),
      );
      try {
        await expectLater(
          task.evaluateBoolean('text', BooleanQuestion('A condition.')),
          throwsA(
            isA<TaskException>()
                .having((error) => error.statusCode, 'statusCode', 13)
                .having(
                  (error) => error.message,
                  'message',
                  allOf(
                    startsWith('EG2 embedder invocation failed.'),
                    contains('UP-053'),
                  ),
                ),
          ),
        );
      } finally {
        await task.dispose();
      }
    },
    skip: textOnly == null
        ? 'set MEDIAPIPE_DECISION_EG2_TEXT_MODEL to the 270M model'
        : perFamily
        ? null
        : 'the wheel library runs the model',
  );

  test('Google\'s failures are TaskExceptions', () async {
    await expectLater(
      DecisionMaker.create(
        DecisionMakerOptions(modelPath: '/nonexistent/laya_s256.task'),
      ),
      throwsA(isA<TaskException>()),
    );
  });
}

/// Every reference case on [model] against Google's answers from its own
/// Python API in `test/fixtures/`[fixture] (tool/generate_reference.py).
void _suite(String label, String model, String fixture, String? absent) {
  final answers =
      jsonDecode(File('test/fixtures/$fixture').readAsStringSync())
          as Map<String, Object?>;
  // The references come from Google's wheel on macOS arm64, where Google's
  // per-family library answers to float32 precision; another host's build of
  // Google's library may differ slightly.
  final tolerance = _host == 'macos/arm64' ? 1e-6 : 0.02;
  late DecisionMaker task;

  setUpAll(() async {
    if (absent != null) return;
    task = await DecisionMaker.create(DecisionMakerOptions(modelPath: model));
  });
  tearDownAll(() async {
    if (absent == null) await task.dispose();
  });

  for (final raw in answers['cases']! as List) {
    final reference = raw as Map<String, Object?>;
    final name = reference['name']! as String;
    final texts = (reference['texts']! as List).cast<String>();
    final expected = (reference['results']! as List)
        .cast<Map<String, Object?>>();
    final json = reference['question']! as Map<String, Object?>;
    test('$label: $name matches Google\'s Python API', skip: absent, () async {
      switch (reference['kind']) {
        case 'boolean':
          final question = BooleanQuestion(
            json['condition']! as String,
            threshold: (json['threshold']! as num).toDouble(),
            normalizePrior: json['normalizePrior']! as bool,
          );
          final batch = await task.evaluateBooleanBatch(texts, question);
          for (var i = 0; i < texts.length; i++) {
            for (final result in [
              await task.evaluateBoolean(texts[i], question),
              batch[i],
            ]) {
              expect(result.value, expected[i]['value']);
              _near(
                result.probabilityTrue,
                expected[i]['probabilityTrue'],
                tolerance,
              );
              _near(result.confidence, expected[i]['confidence'], tolerance);
            }
          }
        case 'choice':
          final question = ChoiceQuestion(
            (json['criteria']! as Map).cast<String, String>(),
            instructions: json['instructions'] as String?,
          );
          final batch = await task.evaluateChoiceBatch(texts, question);
          for (var i = 0; i < texts.length; i++) {
            for (final result in [
              await task.evaluateChoice(texts[i], question),
              batch[i],
            ]) {
              final want = expected[i];
              expect(result.selectedKey, want['selectedKey']);
              expect(
                result.probabilities.keys,
                question.criteria.keys,
                reason: 'probabilities come in the question\'s order',
              );
              final probabilities = want['probabilities']! as Map;
              for (final key in question.criteria.keys) {
                _near(
                  result.probabilities[key]!,
                  probabilities[key],
                  tolerance,
                );
              }
              _near(result.confidence, want['confidence'], tolerance);
              expect(result.predictionSet, want['predictionSet']);
            }
          }
        case 'score':
          final question = ScoreQuestion(
            (json['rubric']! as List).cast<String>(),
            instructions: json['instructions'] as String?,
          );
          final batch = await task.evaluateScoreBatch(texts, question);
          for (var i = 0; i < texts.length; i++) {
            for (final result in [
              await task.evaluateScore(texts[i], question),
              batch[i],
            ]) {
              final want = expected[i];
              _near(result.expectedScore, want['expectedScore'], tolerance);
              final probabilities = want['probabilities']! as List;
              expect(result.probabilities, hasLength(probabilities.length));
              for (var j = 0; j < probabilities.length; j++) {
                _near(result.probabilities[j], probabilities[j], tolerance);
              }
              _near(result.confidence, want['confidence'], tolerance);
              expect(result.selectedKey, want['selectedKey']);
            }
          }
      }
    });
  }
}

void _near(double actual, Object? expected, double tolerance) =>
    expect(actual, closeTo((expected! as num).toDouble(), tolerance));
