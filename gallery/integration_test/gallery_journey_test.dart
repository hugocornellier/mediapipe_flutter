import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_vision/capabilities.dart';
import 'package:mediapipe_gallery/audio_page.dart';
import 'package:mediapipe_gallery/catalog.dart';
import 'package:mediapipe_gallery/live_page.dart';
import 'package:mediapipe_gallery/main.dart';
import 'package:mediapipe_gallery/segment_page.dart';
import 'package:mediapipe_gallery/text_page.dart';

/// Runs every page exposed by this build through the same shell and sidebar a
/// user opens. The picker supplies bundled image bytes without a device file
/// dialog; decoding, task creation, inference and result rendering stay real.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every sidebar task opens and runs its bundled sample', (
    tester,
  ) async {
    // A tap that lands on something else, such as a closing drawer's scrim,
    // fails at that tap instead of several steps later.
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
    final setup = await tester.runAsync(
      () async => (
        await GalleryAssets.unpack(),
        (await queryObjectDetectorCapabilities()).platform,
      ),
    );
    expect(setup, isNotNull);
    final (assets, platform) = setup!;
    final tasks =
        supportedTasks(
          platform,
          assets.bundledTasks,
          assets.officialMacosLandmarkTasks,
        ).where((task) => task.hasOwnPage).toList()..sort((a, b) {
          final category = a.category.index.compareTo(b.category.index);
          return category != 0 ? category : a.title.compareTo(b.title);
        });
    expect(tasks, isNotEmpty);

    Uint8List? imageBytes;
    String? imageName;
    await tester.pumpWidget(
      GalleryApp(
        stillImagePicker: () async {
          expect(imageBytes, isNotNull);
          return XFile.fromData(
            imageBytes!,
            name: imageName!,
            mimeType: 'image/jpeg',
          );
        },
      ),
    );
    // The shell's content pane exists in both layouts; the sidebar's "Home"
    // is inside a closed drawer on phones.
    await _until(
      tester,
      () => find.byKey(const ValueKey('gallery-content')).evaluate().isNotEmpty,
    );

    final visited = <String>[];
    for (final task in tasks) {
      // One line per page, so a stalled run shows where it stopped.
      // ignore: avoid_print
      print('GALLERY_JOURNEY_PAGE ${task.id}');
      if (tester.getSize(find.byType(HomePage)).width < 900) {
        await tester.tap(find.byTooltip('Open navigation'));
        await _settle(tester);
      }
      final sidebar = find.byKey(const ValueKey('gallery-sidebar'));
      final tile = find.descendant(
        of: sidebar,
        matching: find.widgetWithText(ListTile, task.title),
      );
      await tester.scrollUntilVisible(
        tile,
        250,
        scrollable: find
            .descendant(of: sidebar, matching: find.byType(Scrollable))
            .first,
      );
      // scrollUntilVisible ends by jumping the list without a frame, so the
      // tile's position is stale until the list is laid out again.
      await _settle(tester);
      expect(tile, findsOneWidget, reason: task.id);
      await tester.tap(tile);
      await tester.pump();
      // On phones the drawer closes over the new page, and its scrim takes
      // every tap until the drawer has gone.
      await _until(tester, () => find.byType(Drawer).evaluate().isEmpty);
      await _until(
        tester,
        () => find
            .byType(
              task.demo == GalleryDemo.live
                  ? LivePage
                  : task.demo == GalleryDemo.segment
                  ? SegmentPage
                  : task.demo == GalleryDemo.text
                  ? TextPage
                  : AudioPage,
            )
            .evaluate()
            .isNotEmpty,
      );

      switch (task.demo) {
        case GalleryDemo.live:
          final data = await tester.runAsync(
            () => rootBundle.load('assets/samples/${task.sample}'),
          );
          expect(data, isNotNull);
          imageBytes = Uint8List.fromList(
            data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          imageName = task.sample;
          final mode = find.byWidgetPredicate(
            (widget) => widget is DropdownButton,
          );
          expect(mode, findsOneWidget, reason: task.id);
          await tester.tap(mode);
          await _settle(tester);
          await tester.tap(find.text('Still image').last);
          await tester.pump();
          await _until(
            tester,
            () => find.text('Choose image').evaluate().isNotEmpty,
          );
          await tester.tap(find.text('Choose image'));
          final expected = _stillResults[task.runtimeId];
          expect(expected, isNotNull, reason: '${task.id} needs a result');
          await _until(
            tester,
            () => find
                .byWidgetPredicate(
                  (widget) =>
                      widget is Text && expected!.hasMatch(widget.data ?? ''),
                )
                .evaluate()
                .isNotEmpty,
          );
          break;
        case GalleryDemo.text:
          await tester.tap(
            find.text(task.runtimeId == 'text_embedder' ? 'Compare' : 'Run'),
          );
          await _until(
            tester,
            () => find.textContaining('Done in').evaluate().isNotEmpty,
          );
          if (task.runtimeId == 'text_embedder') {
            expect(find.textContaining('Cosine similarity:'), findsOneWidget);
          } else {
            final category = _textCategories[task.runtimeId];
            expect(category, isNotNull, reason: '${task.id} needs a result');
            final row = find
                .ancestor(of: find.text(category!), matching: find.byType(Row))
                .first;
            final score = tester
                .widgetList<Text>(
                  find.descendant(of: row, matching: find.byType(Text)),
                )
                .last;
            expect(
              double.parse(score.data!),
              greaterThanOrEqualTo(0.5),
              reason: task.id,
            );
          }
          break;
        case GalleryDemo.audio:
          await _until(
            tester,
            () => find.textContaining('Done in').evaluate().isNotEmpty,
          );
          expect(find.text('Speech'), findsWidgets);
          break;
        case GalleryDemo.segment:
          await _until(
            tester,
            () => find.text('Include').evaluate().isNotEmpty,
          );
          final canvas = find.byKey(const ValueKey('segment-canvas'));
          await _until(tester, () => canvas.evaluate().isNotEmpty);
          expect(
            canvas,
            findsOneWidget,
            reason: tester
                .widgetList<Text>(find.byType(Text))
                .map((text) => text.data)
                .whereType<String>()
                .join(' | '),
          );
          await tester.tap(canvas);
          await _until(
            tester,
            () => find.textContaining('requests,').evaluate().isNotEmpty,
          );
          break;
        case GalleryDemo.none:
          fail('${task.id} has no page');
      }
      visited.add(task.id);
    }
    expect(visited, hasLength(tasks.length));
    // ignore: avoid_print
    print('GALLERY_JOURNEY ${visited.join(',')}');
  }, timeout: const Timeout(Duration(minutes: 15)));
}

/// A still image result that proves inference found something, not merely
/// that it finished: "0 faces detected" or "No pose detected" fail.
final _stillResults = <String, RegExp>{
  'face_detector': RegExp(r'^[1-9]\d* faces? detected$'),
  'face_landmarker': RegExp(r'^[1-9]\d* faces? detected$'),
  'gesture_recognizer': RegExp(r'^[1-9]\d* hands? recognized$'),
  'hand_landmarker': RegExp(r'^[1-9]\d* hands? detected$'),
  'holistic_landmarker': RegExp(r'^Body landmarks detected$'),
  'image_classifier': RegExp(r'^[1-9]\d* classes returned$'),
  'image_embedder': RegExp(r'^[1-9]\d* embeddings generated$'),
  'image_segmenter': RegExp(r'^Segmentation complete$'),
  'object_detector': RegExp(r'^[1-9]\d* objects? detected$'),
  'pose_landmarker': RegExp(r'^[1-9]\d* poses? detected$'),
};

/// The category each text page's sample belongs to. It must score at least
/// 0.5, so a run that lists it among weak results fails.
const _textCategories = <String, String>{
  'language_detector': 'fr',
  'text_classifier': 'positive',
};

/// Lets a drawer or menu finish animating. Unlike pumpAndSettle it gives up
/// after a few seconds, because a live camera preview never stops scheduling
/// frames.
Future<void> _settle(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  do {
    await tester.pump(const Duration(milliseconds: 100));
  } while (tester.binding.hasScheduledFrame && DateTime.now().isBefore(end));
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 480; i++) {
    await tester.pump();
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
  }
  fail('Gallery action timed out');
}
