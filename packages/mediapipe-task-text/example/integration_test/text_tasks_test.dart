import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:example/language_detection_demo.dart';
import 'package:example/text_classification_demo.dart';
import 'package:example/text_embedding_demo.dart';

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for text task');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(tester.takeException(), isNull);
}

Future<void> submit(WidgetTester tester) async {
  final button = find.byType(FloatingActionButton);
  await waitFor(
    tester,
    () => tester.widget<FloatingActionButton>(button).onPressed != null,
  );
  await tester.tap(button, warnIfMissed: true);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('BERT classifies a Flutter asset with the official score', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TextClassificationDemo()));
    await submit(tester);
    await waitFor(
      tester,
      () => find.text('positive :: 0.9922').evaluate().isNotEmpty,
    );
    expect(find.text('positive :: 0.9922'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('LanguageDetector predicts Spanish from the Flutter asset', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LanguageDetectionDemo()));
    await submit(tester);
    await waitFor(
      tester,
      () => find.textContaining('es ::').evaluate().isNotEmpty,
    );
    expect(find.textContaining('es ::'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('USE embeds, compares, and reloads after an option change', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TextEmbeddingDemo()));
    await tester.enterText(find.byType(TextField), 'Hello, world!');
    await submit(tester);
    await waitFor(
      tester,
      () =>
          find.byType(TextEmbedderResultDisplay).evaluate().length == 1 &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await submit(tester);
    await waitFor(tester, () => find.text('Compare').evaluate().isNotEmpty);
    await tester.ensureVisible(find.text('Compare'));
    await tester.tap(find.text('Compare'), warnIfMissed: true);
    await waitFor(
      tester,
      () => find.byType(ComparisonDisplay).evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<ComparisonDisplay>(find.byType(ComparisonDisplay))
          .similarity,
      closeTo(1, 1e-9),
    );
    await tester.ensureVisible(find.byType(Checkbox).first);
    await tester.tap(find.byType(Checkbox).first, warnIfMissed: true);
    await tester.pump();
    await submit(tester);
    await waitFor(
      tester,
      () =>
          find.byType(TextEmbedderResultDisplay).evaluate().length == 3 &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(find.text('Float'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
