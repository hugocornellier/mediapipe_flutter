import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_segmenter/editor_controller.dart';
import 'package:mediapipe_segmenter/editor_geometry.dart';
import 'package:mediapipe_segmenter/mask_overlay.dart';

class FakeBackend implements SegmentationBackend {
  final calls = <List<SegmentationStroke>>[];
  final results = <Completer<SegmentationMask>>[];
  int images = 0;
  int closed = 0;

  @override
  Future<void> setImage(VisionImage image) async => images++;
  @override
  Future<SegmentationMask> segment(List<SegmentationStroke> strokes) {
    calls.add(strokes);
    final result = Completer<SegmentationMask>();
    results.add(result);
    return result.future;
  }

  @override
  Future<void> dispose() async => closed++;

  void finish(int index, [double confidence = 1]) => results[index].complete(
    SegmentationMask(
      width: 1,
      height: 1,
      confidence: Float32List.fromList([confidence]),
    ),
  );
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
SegmentationPoint point(double x, [double y = 0.5]) =>
    SegmentationPoint(x: x, y: y);
VisionImage input() => VisionImage.fromPixels(
  pixels: Uint8List(3),
  width: 1,
  height: 1,
  format: VisionPixelFormat.rgb,
);

void main() {
  late FakeBackend backend;
  late EditorController editor;
  setUp(() async {
    backend = FakeBackend();
    editor = EditorController(backend);
    await editor.loadImage(input());
  });
  tearDown(() async {
    for (var i = 0; i < backend.results.length; i++) {
      if (!backend.results[i].isCompleted) backend.finish(i);
    }
    await editor.close();
    editor.dispose();
  });

  test(
    'drag coalesces to latest complete history without parallel inference',
    () async {
      editor.begin(point(0.2));
      await tick();
      expect(backend.calls, hasLength(1));
      expect(backend.calls.first.single.isCompleted, isFalse);
      for (var i = 21; i < 80; i++) {
        editor.extend(point(i / 100));
      }
      editor.end();
      expect(backend.calls, hasLength(1));
      expect(editor.coalescedRequests, greaterThan(50));
      backend.finish(0, 0.2);
      await tick();
      expect(editor.mask, isNull);
      expect(backend.calls, hasLength(2));
      expect(backend.calls.last.single.isCompleted, isTrue);
      expect(backend.calls.last.single.points.last.x, 0.79);
      // The active native snapshot was never mutated by later pointer events.
      expect(backend.calls.first.single.points, hasLength(1));
      backend.finish(1, 0.8);
      await tick();
      expect(editor.mask!.confidence.single, closeTo(0.8, 1e-6));
      expect(editor.busy, isFalse);
    },
  );

  test('image replacement drops queued history and obsolete mask', () async {
    editor.begin(point(0.2));
    await tick();
    editor.extend(point(0.3));
    await editor.loadImage(input());
    editor
      ..begin(point(0.7))
      ..end();
    backend.finish(0);
    await tick();
    expect(editor.mask, isNull);
    expect(backend.calls, hasLength(2));
    expect(backend.calls.last.single.points.single.x, 0.7);
    backend.finish(1);
    await tick();
    expect(editor.mask, isNotNull);
    expect(backend.images, 2);
  });

  test(
    'undo resubmits full shorter history; clear never segments empty',
    () async {
      editor
        ..begin(point(0.2))
        ..end();
      await tick();
      backend.finish(0);
      await tick();
      editor.brush = SegmentationBrushMode.negative;
      editor
        ..begin(point(0.4))
        ..end();
      await tick();
      expect(backend.calls.last, hasLength(2));
      expect(backend.calls.last.last.brushMode, SegmentationBrushMode.negative);
      backend.finish(1);
      await tick();
      editor.undo();
      await tick();
      expect(backend.calls.last, hasLength(1));
      backend.finish(2);
      await tick();
      editor.undo();
      await tick();
      expect(editor.mask, isNull);
      expect(editor.strokes, isEmpty);
      expect(backend.calls, hasLength(3));
      expect(backend.images, 2);
    },
  );

  test('lasso waits for a polygon and closes the completed stroke', () async {
    editor.brush = SegmentationBrushMode.lasso;
    editor
      ..begin(point(0.1, 0.1))
      ..extend(point(0.9, 0.1));
    await tick();
    expect(backend.calls, isEmpty);
    editor.extend(point(0.5, 0.9));
    await tick();
    expect(backend.calls.single.single.isCompleted, isFalse);
    editor.end();
    backend.finish(0);
    await tick();
    final stroke = backend.calls.last.single;
    expect(stroke.isCompleted, isTrue);
    expect(stroke.points, hasLength(4));
    expect(stroke.points.first, same(stroke.points.last));
    backend.finish(1);
    await tick();
  });

  test('clear during inference prevents late selection reappearing', () async {
    editor.begin(point(0.2));
    await tick();
    await editor.clear();
    backend.finish(0);
    await tick();
    expect(editor.mask, isNull);
    expect(editor.ready, isTrue);
    expect(editor.strokes, isEmpty);
    expect(backend.calls, hasLength(1));
  });

  test(
    'native failure can be reset; close drains once without notification',
    () async {
      editor
        ..begin(point(0.2))
        ..end();
      await tick();
      backend.results[0].completeError(StateError('decoder failure'));
      await tick();
      expect(editor.ready, isFalse);
      expect(editor.error, contains('decoder failure'));
      await editor.clear();
      editor
        ..begin(point(0.3))
        ..end();
      await tick();
      var notifications = 0;
      editor.addListener(() => notifications++);
      final closing = editor.close();
      expect(editor.close(), same(closing));
      backend.finish(1);
      await closing;
      expect(backend.closed, 1);
      expect(notifications, 0);
      expect(editor.mask, isNull);
    },
  );

  test('letterboxing maps clicks to exact input coordinates at any aspect', () {
    final wide = containedImageRect(
      const Size(1200, 600),
      const Size(800, 600),
    );
    expect(wide, const Rect.fromLTWH(0, 100, 800, 400));
    expect(imagePoint(const Offset(400, 50), wide), isNull);
    expect(imagePoint(const Offset(0, 100), wide)!.x, 0);
    expect(imagePoint(const Offset(800, 500), wide)!.y, 1);
    expect(imagePoint(const Offset(528, 320), wide)!.x, 0.66);
    final tall = containedImageRect(
      const Size(600, 1200),
      const Size(800, 600),
    );
    expect(tall, const Rect.fromLTWH(250, 0, 300, 600));
    expect(imagePoint(const Offset(249, 300), tall), isNull);
    expect(imagePoint(const Offset(400, 300), tall)!.x, 0.5);
  });

  test(
    'threshold changes only overlay bytes, preserving original confidence',
    () {
      final values = Float32List.fromList([0, 0.25, 0.5, 1]);
      final low = maskRgba(values, 0.5);
      final high = maskRgba(values, 0.75);
      expect([low[3], low[7], low[11], low[15]], [0, 0, 115, 115]);
      expect([high[3], high[7], high[11], high[15]], [0, 0, 0, 115]);
    expect(values, [0, 0.25, 0.5, 1]);
    expect(low.sublist(8, 12), [30, 107, 82, 115]);
    },
  );
}
