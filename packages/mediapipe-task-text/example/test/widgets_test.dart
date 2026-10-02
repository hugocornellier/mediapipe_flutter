import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_text/mediapipe_text.dart';
import 'package:example/language_detection_demo.dart';
import 'package:example/text_classification_demo.dart';

Future<TextClassifierResult> fakeClassify(String text) {
  return Future.value(
    TextClassifierResult(
      classifications: <Classifications>[
        Classifications(
          categories: <MediaPipeCategory>[
            MediaPipeCategory(
              index: 0,
              score: 0.9,
              categoryName: 'happy-go-lucky',
              displayName: 'Happy go Lucky',
            ),
          ],
          headIndex: 0,
          headName: 'whatever',
        ),
      ],
    ),
  );
}

Future<LanguageDetectorResult> fakeDetect(String text) {
  return Future.value(
    LanguageDetectorResult(
      predictions: <LanguagePrediction>[
        LanguagePrediction(languageCode: 'es', probability: 0.99),
        LanguagePrediction(languageCode: 'en', probability: 0.01),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('TextClassificationResult should show results', (
    WidgetTester tester,
  ) async {
    final app = MaterialApp(
      home: TextClassificationDemo(classify: fakeClassify),
    );

    await tester.pumpWidget(app);
    await tester.tap(find.byType(Icon));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('Classification::"Hello, world!" 1')),
      findsOneWidget,
    );
    expect(find.text('Happy go Lucky :: 0.9'), findsOneWidget);
  });

  testWidgets('LanguageDetectorResult should show results', (
    WidgetTester tester,
  ) async {
    final app = MaterialApp(home: LanguageDetectionDemo(detect: fakeDetect));

    await tester.pumpWidget(app);
    await tester.tap(find.byType(Icon));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('prediction-"Quiero agua, por favor" 1')),
      findsOneWidget,
    );
    expect(find.text('es :: 0.99'), findsOneWidget);
    expect(find.text('en :: 0.01'), findsOneWidget);
  });
}
