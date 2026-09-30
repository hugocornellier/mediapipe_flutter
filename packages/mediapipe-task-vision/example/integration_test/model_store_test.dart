import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_core/model_store.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';
import 'package:mediapipe_vision/models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('downloads a real model once and loads its verified cache', (
    tester,
  ) async {
    expect(Platform.isMacOS || Platform.isIOS, isTrue);
    final store = ModelStore();
    await store.clear();
    final pin = visionModels['blaze_face_short_range']!;
    final first = await store.get(pin);
    expect(await first.length(), greaterThan(0));
    final offline = DownloadAsset(
      url: 'https://invalid.example/model',
      sha256: pin.sha256,
    );
    final second = await store.get(offline);
    expect(second.path, first.path);
    final detector = await FaceDetector.create(
      FaceDetectorOptions(modelPath: second.path),
    );
    await detector.dispose();
  });
}
