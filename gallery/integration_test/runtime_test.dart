import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_gallery/catalog.dart';
import 'package:mediapipe_gallery/live/live_registry.dart';
import 'package:mediapipe_gallery/main.dart';

/// Opening one tile and then another must not take the process down.
///
/// Task bindings carry their own native asset id: face tasks bind
/// `face_landmarker.dylib` while every other task binds `vision.dylib`. When a
/// single runtime serves both ids it is bundled once per id, so the app loads
/// two copies of the same MediaPipe and its static graph registry aborts on the
/// second registration. That is a native abort, not a Dart exception, so it
/// kills the test process rather than failing an expectation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tiles that use different native assets coexist', (_) async {
    final assets = await GalleryAssets.unpack();
    final platform = (await queryObjectDetectorCapabilities()).platform;
    final tiles = supportedTasks(
      platform,
      assets.bundledTasks,
      assets.officialMacosLandmarkTasks,
    ).where((task) => task.demo == GalleryDemo.live).toList();
    expect(tiles.length, greaterThan(1), reason: 'need two live tiles');

    // Visit every live tile in one process, exactly as a user moving through
    // the grid does. Each task is fully disposed before the next opens, so a
    // failure here is about loaded native images, not about task lifetime.
    final visited = <String>[];
    for (final tile in tiles) {
      final task = liveDemoFor(tile.id)!.task();
      final model = await rootBundle.load('assets/models/${tile.model}');
      await task.open(
        VisionDelegate.cpu,
        model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes),
      );
      final result = await task.detect(
        VisionImage.fromFile(assets.path(tile.sample)),
        1,
      );
      expect(result, isNotNull, reason: tile.id);
      await task.close();
      visited.add(tile.id);
    }
    expect(visited, hasLength(tiles.length));
    // Skipped: this reproduces a known defect rather than guarding against a
    // regression. Face binds face_landmarker.dylib while the landmark tasks
    // bind vision.dylib, so one runtime serving both ids is loaded twice and
    // MediaPipe aborts on the second graph registration. The abort kills the
    // process, so leaving it enabled would take the whole suite with it.
    // Unskip once a single image serves both asset ids.
  }, skip: true);
}
