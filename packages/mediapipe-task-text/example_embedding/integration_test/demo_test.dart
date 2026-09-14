import 'package:embedding_gemma_demo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_text/text_summarizer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
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
    await tester.tap(find.text('Compare sentences'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final first = double.parse(
      tester.widget<Text>(find.byKey(const Key('similarity-score'))).data!,
    );
    await tester.enterText(
      find.byKey(const Key('second-sentence')),
      'The database migration added three indexes.',
    );
    await tester.tap(find.text('Compare sentences'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
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
    await tester.tap(find.byKey(const Key('proofread-button')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
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
