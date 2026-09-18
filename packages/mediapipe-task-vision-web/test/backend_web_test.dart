@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/interface.dart';
import 'package:mediapipe_flutter_vision_web/mediapipe_flutter_vision_web.dart';

void main() {
  test(
    'validates model options and rejects unsupported delegate explicitly',
    () async {
      // Browser unit-test asset serving differs from the deployed package path;
      // the full API is exercised through the gallery integration harness.
      expect(
        () => FaceLandmarkerOptions(modelBytes: Uint8List(0)),
        throwsArgumentError,
      );
      final error = WebFaceLandmarker.create(
        FaceLandmarkerOptions(
          modelBytes: Uint8List.fromList([1]),
          delegate: VisionDelegate.gpu,
        ),
      );
      await expectLater(error, throwsUnsupportedError);
    },
  );
}
