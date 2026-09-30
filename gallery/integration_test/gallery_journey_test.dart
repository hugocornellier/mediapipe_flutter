import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_vision/capabilities.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';
import 'package:mediapipe_gallery/audio_page.dart';
import 'package:mediapipe_gallery/catalog.dart';
import 'package:mediapipe_gallery/live/live_camera_view.dart';
import 'package:mediapipe_gallery/live_page.dart';
import 'package:mediapipe_gallery/main.dart';
import 'package:mediapipe_gallery/segment_page.dart';
import 'package:mediapipe_gallery/text_page.dart';
import 'package:mediapipe_gallery/ui/components.dart';
import 'package:mediapipe_gallery/ui/design.dart';

import 'support/delegate_control.dart';

/// GPU coverage follows the SDK suites: 'required' on physical phones fails a
/// GPU refusal, 'skip' on emulators and simulators never tries GPU, and the
/// default 'optional' tries it and keeps to CPU after the first refusal.
const _gpu = String.fromEnvironment('SDK_GPU', defaultValue: 'optional');
const _gpuSkipTasks = String.fromEnvironment('SDK_GPU_SKIP_TASKS');

/// Runs every page exposed by this build through the same shell and sidebar a
/// user opens: each camera page live on every delegate it offers, switched
/// while running, then a still image on each; the segmenter, text and audio
/// pages on theirs. The picker supplies bundled image bytes without a device
/// file dialog; decoding, task creation, inference and rendering stay real.
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

    var gpuRefused = false;
    Set<VisionDelegate> offered(GalleryTask task) => task
        .capabilitiesFor(platform, assets.officialMacosLandmarkTasks)
        .supportedDelegates;
    // The delegates this run exercises, in the order a user would try them.
    List<VisionDelegate> delegatesFor(GalleryTask task) => [
      if (offered(task).contains(VisionDelegate.cpu)) VisionDelegate.cpu,
      if (offered(task).contains(VisionDelegate.gpu) &&
          _gpu != 'skip' &&
          !gpuRefused &&
          !_gpuSkipTasks.split(',').contains(task.runtimeId))
        VisionDelegate.gpu,
    ];

    final visited = <String>[];
    final checks = <String>[];
    for (final task in tasks) {
      // One line per page, so a stalled run shows where it stopped.
      // ignore: avoid_print
      print('GALLERY_JOURNEY_PAGE ${task.id}');
      // Below the design's wide breakpoint the sidebar is a drawer.
      if (tester.getSize(find.byType(HomePage)).width < Sizes.wide) {
        await tester.tap(find.byTooltip('Open navigation'));
        await _settle(tester);
      }
      final sidebar = find.byKey(const ValueKey('gallery-sidebar'));
      final tile = find.descendant(
        of: sidebar,
        matching: find.text(task.title),
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
          final choices = offered(task).length > 1;
          final delegates = delegatesFor(task);
          expect(delegates, isNotEmpty, reason: task.id);
          final camera = await _cameraProblem(tester);
          if (camera != null) {
            // Emulators and phones have cameras; desktop runners and
            // simulators may not.
            expect(
              defaultTargetPlatform,
              isNot(TargetPlatform.android),
              reason: '${task.id}: $camera',
            );
            checks.add('${task.id}:camera:none');
            _note('${task.id}: no camera ($camera)');
          } else {
            for (final delegate in delegates) {
              if (choices) await tapDelegate(tester, delegate);
              final optional =
                  delegate == VisionDelegate.gpu && _gpu == 'optional';
              if (!await _liveFrames(tester, delegate, optional: optional)) {
                gpuRefused = true;
                _note(
                  '${task.id}: live GPU refused, CPU from here: ${_screen(tester)}',
                );
                await tapDelegate(tester, VisionDelegate.cpu);
                break;
              }
              checks.add('${task.id}:${delegate.name}:live');
            }
          }
          final still = find.byKey(
            ValueKey('${task.runtimeId.replaceAll('_', '-')}-mode-image'),
          );
          expect(still, findsOneWidget, reason: task.id);
          await tester.ensureVisible(still);
          await tester.tap(still);
          await tester.pump();
          await _until(
            tester,
            () => find.text('Choose image').evaluate().isNotEmpty,
          );
          await tester.ensureVisible(find.text('Choose image'));
          await tester.tap(find.text('Choose image'));
          final expected = _stillResults[task.runtimeId];
          expect(expected, isNotNull, reason: '${task.id} needs a result');
          // Each delegate runs the image again, the last one first since the
          // page is already on it.
          for (final delegate in delegatesFor(task).reversed) {
            if (choices) await tapDelegate(tester, delegate);
            final optional =
                delegate == VisionDelegate.gpu && _gpu == 'optional';
            if (!await _stillRan(
              tester,
              delegate,
              expected!,
              optional: optional,
            )) {
              gpuRefused = true;
              _note(
                '${task.id}: still GPU refused, CPU from here: ${_screen(tester)}',
              );
              continue;
            }
            checks.add('${task.id}:${delegate.name}:still');
          }
          expect(
            checks.where(
              (check) =>
                  check.startsWith('${task.id}:') && check.endsWith(':still'),
            ),
            isNotEmpty,
            reason: '${task.id} ran no still image',
          );
          break;
        case GalleryDemo.text:
          checks.add('${task.id}:cpu:run');
          final run = find.text(
            task.runtimeId == 'text_embedder' ? 'Compare' : 'Run',
          );
          await tester.ensureVisible(run);
          await tester.tap(run);
          await _until(
            tester,
            () => find.textContaining('Done in').evaluate().isNotEmpty,
          );
          if (task.runtimeId == 'text_embedder') {
            expect(find.text('Cosine similarity'), findsOneWidget);
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
          checks.add('${task.id}:cpu:run');
          await _until(
            tester,
            () => find.textContaining('Done in').evaluate().isNotEmpty,
          );
          expect(find.text('Speech'), findsWidgets);
          break;
        case GalleryDemo.segment:
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
          await tester.ensureVisible(canvas);
          await tester.tap(canvas);
          for (final (index, delegate) in delegatesFor(task).indexed) {
            if (index > 0) {
              // Switching reopens the task, so the image is tapped again.
              await tapDelegate(tester, delegate);
              await _until(tester, () => canvas.evaluate().isNotEmpty);
              await _settle(tester);
              await tester.tap(canvas);
            }
            final label = delegate == VisionDelegate.gpu ? 'GPU' : 'CPU';
            await _until(
              tester,
              () => _status(tester).any(
                (status) =>
                    status.delegate == label &&
                    status.parts.any(RegExp(r'^\d+ requests$').hasMatch),
              ),
            );
            checks.add('${task.id}:${delegate.name}:tap');
          }
          break;
        case GalleryDemo.none:
          fail('${task.id} has no page');
      }
      visited.add(task.id);
    }
    expect(visited, hasLength(tasks.length));
    // ignore: avoid_print
    print('GALLERY_JOURNEY ${visited.join(',')}');
    // ignore: avoid_print
    print('GALLERY_JOURNEY_CHECKS ${checks.join(',')}');
  }, timeout: const Timeout(Duration(minutes: 20)));
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

/// Waits for a camera page to open its camera: null once frames arrive, or
/// the page's message when it has no camera or could not open one.
Future<String?> _cameraProblem(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    final view = find.byType(LiveCameraView);
    if (view.evaluate().isNotEmpty) {
      final live = tester.widget<LiveCameraView>(view);
      if (live.controller.running && live.controller.recentFrames > 0) {
        return null;
      }
      if (live.placeholder case final Text message) {
        return message.data ?? 'camera error';
      }
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
  }
  fail('The camera page neither ran nor reported a problem');
}

/// The status lines under the page's feed.
Iterable<FeedStatus> _status(WidgetTester tester) =>
    tester.widgetList<FeedStatus>(find.byType(FeedStatus));

/// Waits for the live stats line to count frames on [delegate]. An [optional]
/// delegate that errors or stays silent for a minute returns false.
Future<bool> _liveFrames(
  WidgetTester tester,
  VisionDelegate delegate, {
  required bool optional,
}) async {
  final label = delegate == VisionDelegate.gpu ? 'GPU' : 'CPU';
  final deadline = DateTime.now().add(Duration(seconds: optional ? 60 : 120));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    final view = find.byType(LiveCameraView);
    if (view.evaluate().isNotEmpty) {
      final controller = tester.widget<LiveCameraView>(view).controller;
      // Frames counted since the page last started on this delegate, as the
      // status line under the feed reports them.
      if (controller.running &&
          !controller.changing &&
          controller.delegate == delegate &&
          controller.recentFrames > 0 &&
          _status(tester).any((status) => status.delegate == label)) {
        return true;
      }
    }
    if (optional && view.evaluate().isNotEmpty) {
      final live = tester.widget<LiveCameraView>(view);
      if (live.controller.delegate == delegate &&
          (live.controller.error != null || live.placeholder is Text)) {
        return false;
      }
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
  }
  if (optional) return false;
  fail('No live $label frames: ${_screen(tester)}');
}

/// Waits for a still image result from [delegate] that matches [expected]. An
/// [optional] delegate that gives none within a minute returns false.
Future<bool> _stillRan(
  WidgetTester tester,
  VisionDelegate delegate,
  RegExp expected, {
  required bool optional,
}) async {
  final label = delegate == VisionDelegate.gpu ? 'GPU' : 'CPU';
  final ran = RegExp(r'^Inference \d+\.\d ms$');
  final deadline = DateTime.now().add(Duration(seconds: optional ? 60 : 120));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    if (_status(tester).any(
      (status) =>
          status.delegate == label &&
          status.parts.any(ran.hasMatch) &&
          status.parts.any(expected.hasMatch),
    )) {
      return true;
    }
    final error = _imageError(tester);
    if (error != null) {
      if (optional) return false;
      fail('$label still image failed: $error');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
  }
  if (optional) return false;
  fail('No $label still image result matching $expected: ${_screen(tester)}');
}

/// The error a still image page shows in the theme's error colour, if any.
String? _imageError(WidgetTester tester) {
  final page = find.byType(LivePage);
  if (page.evaluate().isEmpty) return null;
  final color = Theme.of(tester.element(page)).colorScheme.error;
  for (final text in tester.widgetList<Text>(
    find.descendant(of: page, matching: find.byType(Text)),
  )) {
    if (text.style?.color == color && (text.data ?? '').isNotEmpty) {
      return text.data;
    }
  }
  return null;
}

/// Every text on screen, for failure messages and notes.
String _screen(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data)
    .whereType<String>()
    .where((text) => text.trim().isNotEmpty)
    .join(' | ');

void _note(String message) {
  // ignore: avoid_print
  print('GALLERY_JOURNEY_NOTE $message');
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
