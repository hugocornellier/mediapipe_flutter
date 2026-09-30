import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_vision/capabilities.dart';
import 'package:mediapipe_gallery/catalog.dart';
import 'package:mediapipe_gallery/live/mask_overlay.dart';
import 'package:mediapipe_gallery/live_page.dart';
import 'package:mediapipe_gallery/main.dart';

/// Seconds to hold each state on screen, so a person can look at it.
const _hold = int.fromEnvironment('SEGMENTER_HOLD_SECONDS');

/// The Image Segmenter page draws its bundled sample as Google's demo does:
/// a smooth mask in the legend's colors, the legend under the view, and the
/// Output Type and Opacity settings, with no connections or points.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Image Segmenter draws Google demo masks', (tester) async {
    final setup = await tester.runAsync(
      () async => (
        await GalleryAssets.unpack(),
        (await queryImageSegmenterCapabilities()).platform,
      ),
    );
    final (assets, platform) = setup!;
    final task = supportedTasks(
      platform,
      assets.bundledTasks,
      assets.officialMacosLandmarkTasks,
    ).singleWhere((task) => task.id == 'image_segmenter_live');
    final sample = await tester.runAsync(
      () => rootBundle.load('assets/samples/${task.sample}'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: _shot,
          child: LivePage(
            task: task,
            platform: platform,
            officialMacosLandmarkTasks: assets.officialMacosLandmarkTasks,
            initialStillImage: true,
            stillImagePicker: () async => XFile.fromData(
              sample!.buffer.asUint8List(
                sample.offsetInBytes,
                sample.lengthInBytes,
              ),
              name: task.sample,
              mimeType: 'image/jpeg',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Choose image'));
    await tester.tap(find.text('Choose image'));
    await _until(tester, () => find.text('Segmentation complete'));
    await _until(tester, () => find.byKey(const ValueKey('segmenter-legend')));
    final legend = find.byKey(const ValueKey('segmenter-legend'));
    for (final label in ['person', 'background']) {
      expect(
        find.descendant(of: legend, matching: find.text(label)),
        findsOneWidget,
      );
    }
    await _hold_(tester, 'category');

    if (find.text('Output Type').evaluate().isEmpty) {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
    }
    expect(find.text('DeepLab V3'), findsOneWidget);
    expect(find.text('Opacity'), findsOneWidget);
    expect(find.text('Connections'), findsNothing);
    expect(find.text('Points'), findsNothing);

    final outputType = find.byKey(
      const ValueKey('setting-outputConfidenceMasks'),
    );
    await tester.ensureVisible(outputType);
    await tester.tap(outputType);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confidence Mask').last);
    // Choosing it clears the result until the rebuilt task answers.
    await _until(tester, () => find.text('Select Class'));
    await _until(tester, () => find.text('Segmentation complete'));
    expect(find.byKey(const ValueKey('segmenter-legend')), findsNothing);

    // Person, as Google's demo would be set to look at the portrait.
    // The menu builds its 21 classes lazily, so the class is chosen through
    // the menu's own callback.
    final classes = find.byKey(const ValueKey('setting-confidenceClass'));
    tester
        .widget<DropdownButton<int>>(
          find.descendant(
            of: classes,
            matching: find.byType(DropdownButton<int>),
          ),
        )
        .onChanged!(15);
    await tester.pump();
    expect(
      find.descendant(of: classes, matching: find.text('person')),
      findsOneWidget,
    );
    await _hold_(tester, 'confidence');
    expect(tester.takeException(), isNull);
  });
}

final _shot = GlobalKey();

/// Gives the mask image a second to build, holds the state on screen, checks
/// a mask is drawn, and saves the view as
/// a PNG in the app's temporary directory.
Future<void> _hold_(WidgetTester tester, String name) async {
  for (var i = 0; i < 10 + _hold * 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  // A mask image exists once the overlay has something to draw.
  final painter = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<MaskOverlay>()
      .single;
  expect(painter.masks.image, isNotNull);
  await tester.runAsync(() async {
    final boundary =
        _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${Directory.systemTemp.path}/segmenter_$name.png');
    await file.writeAsBytes(png!.buffer.asUint8List());
    debugPrint('segmenter shot: ${file.path}');
  });
}

Future<void> _until(
  WidgetTester tester,
  Finder Function() finder, {
  bool optional = false,
}) async {
  for (var i = 0; i < (optional ? 30 : 300); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (finder().evaluate().isNotEmpty) return;
  }
  if (!optional) fail('Timed out waiting for ${finder()}');
}
