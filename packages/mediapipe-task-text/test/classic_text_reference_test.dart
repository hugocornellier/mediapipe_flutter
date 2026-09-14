@Tags(['native-assets'])
library;

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'support/classic_text_validation.dart';

void main() {
  test(
    'all three tasks match official 1.0.1 outputs from paths and bytes',
    () async {
      final report = await validateClassicText(
        {
          'classifier': 'example/assets/bert_classifier.tflite',
          'embedder': 'example/assets/universal_sentence_encoder.tflite',
          'language': 'example/assets/language_detector.tflite',
        },
        jsonDecode(
          File(
            'test/fixtures/classic_text/official_reference.json',
          ).readAsStringSync(),
        ),
      );
      expect(report['reference_cases'], 26);
      expect(report['inference_comparisons'], 52);
      print(jsonEncode(report));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
