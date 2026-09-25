import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_audio/mediapipe_flutter_audio.dart';
import 'package:mediapipe_flutter_text/mediapipe_flutter_text.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_gallery/catalog.dart';
import 'package:mediapipe_gallery/live/live_registry.dart';
import 'package:mediapipe_gallery/main.dart';

/// Opening one tile and then another must not take the process down.
///
/// Task bindings carry their own native asset id: face tasks bind
/// `face_landmarker.dylib` while every other task binds `vision.dylib`. A
/// runtime serving both ids must still be loaded once, or its graph registry
/// aborts on the second registration: the desktop wheels load one image for
/// both ids, Google's macOS monolith is bundled once as `vision.dylib` with
/// face calling through it, and the mobile SDK adapters serve every id from one
/// image. An abort is native, not a Dart exception, so it kills the test
/// process rather than failing an expectation.
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
      final delegates = tile
          .capabilitiesFor(platform, assets.officialMacosLandmarkTasks)
          .supportedDelegates;
      await task.open(
        delegates.contains(VisionDelegate.cpu)
            ? VisionDelegate.cpu
            : delegates.first,
        model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes),
      );
      final result = await task.detect(
        VisionImage.fromFile(assets.path(tile.sample)),
        1,
        rotationDegrees: 0,
      );
      expect(result, isNotNull, reason: tile.id);
      await task.close();
      visited.add(tile.id);
    }
    expect(visited, hasLength(tiles.length));
    // The record of which tiles this platform opened.
    // ignore: avoid_print
    print('RUNTIME_TILES ${visited.join(',')}');
  });

  // Text and audio run on core's shared runtime. On Linux and Windows that is
  // the very library the vision tiles above loaded, mapped once for both; on
  // macOS it is a separate official build whose symbols stay apart.
  testWidgets('text and audio answer in the same process', (tester) async {
    final assets = await GalleryAssets.unpack();
    final bundled = assets.bundledTasks;
    if (!bundled.contains('text_classifier') &&
        !bundled.contains('audio_classifier')) {
      markTestSkipped('This target bundles no text or audio task.');
      return;
    }
    Future<Uint8List> asset(String path) async {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }

    await tester.runAsync(() async {
      if (bundled.contains('text_classifier')) {
        final classifier = await TextClassifier.create(
          TextClassifierOptions.fromAssetBuffer(
            await asset('assets/models/bert_classifier.tflite'),
          ),
        );
        try {
          final result = await classifier.classify('What a wonderful day!');
          expect(
            result.classifications.first.categories.first.categoryName,
            'positive',
          );
        } finally {
          await classifier.dispose();
        }
      }
      if (bundled.contains('audio_classifier')) {
        final classifier = await AudioClassifier.create(
          AudioClassifierOptions(
            modelBytes: await asset('assets/models/yamnet.tflite'),
          ),
        );
        try {
          final chunks = await classifier.classify(
            decodeWav(await asset('assets/samples/speech_16000_hz_mono.wav')),
          );
          expect(chunks.first.categories.first.name, 'Speech');
        } finally {
          await classifier.dispose();
        }
      }
    });
  });
}
