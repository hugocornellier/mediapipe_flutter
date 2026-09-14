import 'package:embedding_gemma_demo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
}
