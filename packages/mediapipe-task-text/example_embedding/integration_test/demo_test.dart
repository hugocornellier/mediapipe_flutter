import 'dart:convert';

import 'package:embedding_gemma_demo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_text/text_summarizer.dart';
import 'package:mediapipe_flutter_text/embedding_gemma.dart';

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

Future<void> waitForSimilarity(WidgetTester tester) async {
  for (var i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byKey(const Key('similarity-score')).evaluate().isNotEmpty) {
      return;
    }
    final errors = find.byType(SelectableText);
    if (errors.evaluate().isNotEmpty) {
      fail(
        'Comparison failed: ${tester.widget<SelectableText>(errors.first).data}',
      );
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  fail('Comparison did not finish within 60 seconds.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'embedding settings run quantized retrieval and reload float output',
    (tester) async {
      await tester.pumpWidget(const EmbeddingDemo());
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('embedding-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tapVisible(tester, find.text('Embedding settings'));
      await tapVisible(tester, find.byKey(const Key('embedding-format')));
      await tester.tap(find.text('Retrieval query').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<TextRole>>(
              find.byKey(const Key('embedding-second-role')),
            )
            .selected,
        {TextRole.document},
      );
      await tapVisible(tester, find.byKey(const Key('embedding-normalize')));
      await tapVisible(tester, find.byKey(const Key('embedding-quantize')));
      await tester.enterText(
        find.byKey(const Key('embedding-second-title')),
        'Animals',
      );
      await tapVisible(tester, find.text('Embedding settings'));
      await tapVisible(tester, find.text('Compare sentences'));
      await waitForSimilarity(tester);
      final quantized = double.parse(
        tester.widget<Text>(find.byKey(const Key('similarity-score'))).data!,
      );
      expect(quantized.isFinite, isTrue);
      expect(find.textContaining('768 int8 values'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Embeddings'),
        200,
        scrollable: scrollable,
      );
      await tapVisible(tester, find.text('Embeddings'));
      final vectorTexts = find.descendant(
        of: find.byKey(const Key('embedding-vectors')),
        matching: find.byType(SelectableText),
      );
      expect(vectorTexts, findsNWidgets(2));
      final vector =
          jsonDecode(tester.widget<SelectableText>(vectorTexts.first).data!)
              as List<dynamic>;
      expect(vector, hasLength(768));
      expect(
        vector.every((value) => value is int && value >= -128 && value <= 127),
        isTrue,
      );
      await tester.scrollUntilVisible(
        find.text('Embedding settings'),
        -200,
        scrollable: scrollable,
      );
      await tapVisible(tester, find.text('Embedding settings'));
      await tapVisible(tester, find.byKey(const Key('embedding-quantize')));
      await tapVisible(tester, find.text('Embedding settings'));
      await tapVisible(tester, find.text('Compare sentences'));
      await waitForSimilarity(tester);
      expect(find.textContaining('768 float32 values'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Embeddings'),
        200,
        scrollable: scrollable,
      );
      await tapVisible(tester, find.text('Embeddings'));
      final floatVector =
          jsonDecode(
                tester
                    .widget<SelectableText>(
                      find
                          .descendant(
                            of: find.byKey(const Key('embedding-vectors')),
                            matching: find.byType(SelectableText),
                          )
                          .first,
                    )
                    .data!,
              )
              as List<dynamic>;
      expect(floatVector, hasLength(768));
      expect(
        floatVector.every((value) => value is num && value.isFinite),
        isTrue,
      );
      final floating = double.parse(
        tester.widget<Text>(find.byKey(const Key('similarity-score'))).data!,
      );
      expect((floating - quantized).abs(), lessThan(.03));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('summarize in key-points streaming and completed TLDR modes', (
    tester,
  ) async {
    await tester.pumpWidget(const EmbeddingDemo());
    await tester.tap(find.text('Summarizer'));
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('summarizer-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.enterText(
      find.byKey(const Key('summarizer-input')),
      'The library will close at six today for maintenance and reopen tomorrow morning.',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('summarize-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('summarize-button')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(
      find.byKey(const Key('summarizer-output')),
      200,
      scrollable: scrollable,
    );
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('summarizer-output')))
          .data,
      '* The library will close at six today for maintenance.\n* The library will reopen tomorrow morning.',
    );
    await tester.scrollUntilVisible(
      find.text('TL;DR'),
      -200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TL;DR'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<TextSummarizerMode>>(
            find.byType(SegmentedButton<TextSummarizerMode>),
          )
          .selected,
      {TextSummarizerMode.tldr},
    );
    await tapVisible(tester, find.byKey(const Key('summarizer-token-budget')));
    await tester.tap(find.text('64 tokens').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('summarizer-streaming')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('summarizer-streaming')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('summarizer-streaming')))
          .value,
      isFalse,
    );
    await tester.ensureVisible(find.byKey(const Key('summarize-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('summarize-button')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(
      find.byKey(const Key('summarizer-output')),
      200,
      scrollable: scrollable,
    );
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('summarizer-output')))
          .data,
      'The library will close for maintenance and reopen tomorrow morning.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('compare sentences with the official model on macOS CPU', (
    tester,
  ) async {
    await tester.pumpWidget(const EmbeddingDemo());
    await tapVisible(tester, find.text('Compare sentences'));
    final first = double.parse(
      tester.widget<Text>(find.byKey(const Key('similarity-score'))).data!,
    );
    await tester.enterText(
      find.byKey(const Key('second-sentence')),
      'The database migration added three indexes.',
    );
    await tapVisible(tester, find.text('Compare sentences'));
    final second = double.parse(
      tester.widget<Text>(find.byKey(const Key('similarity-score'))).data!,
    );
    expect(first, greaterThan(second));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('stream corrections and switch to completed proofreading', (
    tester,
  ) async {
    await tester.pumpWidget(const EmbeddingDemo());
    await tester.tap(find.text('Proofreader'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('proofread-button')));
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('proofreader-output')))
          .data,
      'She went to the store yesterday and bought some apples.',
    );
    expect(find.byKey(const Key('proofreader-timing')), findsOneWidget);
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('proofreader-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('proofreader-edits')),
      200,
      scrollable: scrollable,
    );
    expect(find.byKey(const Key('proofreader-edits')), findsOneWidget);
    final edits = tester
        .widget<SelectableText>(find.byKey(const Key('proofreader-edits')))
        .textSpan!
        .children!
        .cast<TextSpan>();
    expect(
      edits.any(
        (e) =>
            e.text == 'went' && e.style?.decoration == TextDecoration.underline,
      ),
      isTrue,
    );
    expect(
      edits.any(
        (e) =>
            e.text == 'go' && e.style?.decoration == TextDecoration.lineThrough,
      ),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('proofreader-input')),
      -200,
      scrollable: scrollable,
    );
    await tester.enterText(
      find.byKey(const Key('proofreader-input')),
      'I recieved your mesage and will reply tomorow.',
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('proofreader-token-budget')));
    await tester.tap(find.text('256 tokens').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('proofreader-streaming')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proofreader-streaming')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('proofreader-streaming')),
          )
          .value,
      isFalse,
    );
    await tester.ensureVisible(find.byKey(const Key('proofread-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proofread-button')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('proofreader-output')))
          .data,
      'I received your message and will reply tomorrow.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
