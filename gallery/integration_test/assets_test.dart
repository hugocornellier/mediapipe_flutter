import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_vision/capabilities.dart';
import 'package:mediapipe_gallery/catalog.dart';
import 'package:mediapipe_gallery/live/face_camera_controller.dart';
import 'package:mediapipe_gallery/main.dart';

/// `tool/prepare.py` chooses what the app bundles per target, so an asset a
/// screen asks for by name can silently not be there. These check the bundle
/// the app was actually built with.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every visible tile can load its model and sample', (_) async {
    final assets = await GalleryAssets.unpack();
    final platform = (await queryObjectDetectorCapabilities()).platform;
    final tasks = supportedTasks(platform, assets.bundledTasks);
    expect(tasks, isNotEmpty, reason: 'no tile is visible to check');
    for (final task in tasks) {
      await expectLater(
        rootBundle.load('assets/models/${task.model}'),
        completes,
        reason: '${task.id} model',
      );
      await expectLater(
        rootBundle.load('assets/samples/${task.sample}'),
        completes,
        reason: '${task.id} sample',
      );
    }
  });

  testWidgets('the live demo loads its model before touching a camera', (
    _,
  ) async {
    final assets = await GalleryAssets.unpack();
    final platform = (await queryObjectDetectorCapabilities()).platform;
    final live = supportedTasks(platform, assets.bundledTasks)
        .where((task) => task.live)
        .toList();
    if (live.isEmpty) {
      markTestSkipped('no live tile on this platform');
      return;
    }
    final controller = FaceCameraController();
    addTearDown(controller.dispose);
    // The model is loaded before the camera is opened, so this reaches the
    // asset without needing a real device. Opening a camera that does not
    // exist is expected to fail; failing to find the model is the regression.
    // start() reports failures on the controller rather than throwing, which
    // is how this surfaced in the app as a message instead of a crash.
    await controller.start(
      const CameraDescription(
        name: 'gallery-integration-test',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 0,
      ),
      modelAsset: 'assets/models/${live.single.model}',
    );
    expect(
      controller.error ?? '',
      isNot(contains('Unable to load asset')),
      reason: 'the live demo asked for a model asset the bundle does not have',
    );
  });
}
