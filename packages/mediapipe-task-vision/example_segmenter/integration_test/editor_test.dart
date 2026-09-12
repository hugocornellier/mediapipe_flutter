import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_segmenter/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real image editor selects, clears and changes samples', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: boundary, child: const SegmenterApp()),
    );
    Future<void> waitFor(bool Function() condition) async {
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (condition()) return;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      fail('Editor did not settle within 10 seconds.');
    }

    final inference = find.textContaining('ms inference');
    await waitFor(() => inference.evaluate().isNotEmpty);
    expect(find.byKey(const Key('image-canvas')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump();
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final screenshot = await render.toImage(pixelRatio: 1);
    final png = (await screenshot.toByteData(format: ui.ImageByteFormat.png))!;
    screenshot.dispose();
    final directory = await Directory.systemTemp.createTemp(
      'segmenter-editor-',
    );
    final file = File('${directory.path}/editor.png');
    await file.writeAsBytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
    // The host validation transcript records the generated artifact location.
    // ignore: avoid_print
    print('SEGMENTER_SCREENSHOT ${file.path}');

    await tester.tap(find.text('Clear'));
    await waitFor(
      () =>
          inference.evaluate().isEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    final canvas = tester.getRect(find.byKey(const Key('image-canvas')));
    await tester.tapAt(canvas.center);
    await waitFor(() => inference.evaluate().isNotEmpty);
    await tester.tap(find.text('Undo'));
    await waitFor(() => inference.evaluate().isEmpty);
    await tester.tap(find.text('Portrait'));
    await waitFor(
      () => find.textContaining('Portrait ·').evaluate().isNotEmpty,
    );
    expect(inference, findsNothing);
    await tester.tapAt(
      tester.getRect(find.byKey(const Key('image-canvas'))).center,
    );
    await waitFor(() => inference.evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });
}
