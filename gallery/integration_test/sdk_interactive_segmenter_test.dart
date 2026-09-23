import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_flutter_vision/vision_task_backend.dart';
import 'package:mediapipe_gallery/main.dart';

import 'support/official_mask_references.dart';
import 'support/sdk_frames.dart';

// Google's stateful MagicTouch Interactive Segmenter through the official
// mobile SDKs: iOS through the package's Objective-C adapter, Android through
// mediapipe_flutter_vision_android. The reference is CPU. On Android, SDK_GPU
// also tries Google's GPU delegate, which is not declared supported yet:
// `required` fails a refusal, `optional` records it, `skip` runs CPU only.
const _gpu = String.fromEnvironment('SDK_GPU', defaultValue: 'optional');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'official SDK interactive_segmenter: reference, strokes, undo, images',
    (tester) async {
      await tester.runAsync(() async {
        expect(Platform.isAndroid || Platform.isIOS, isTrue);
        if (Platform.isAndroid) {
          expect(interactiveSegmenterBackendFactory, isNotNull);
        }
        final assets = await GalleryAssets.unpack();
        final bytes = await rootBundle.load(
          'assets/models/interactive_segmentation.task',
        );
        final task = await InteractiveSegmenter.create(
          InteractiveSegmenterOptions(
            modelBytes: bytes.buffer.asUint8List(
              bytes.offsetInBytes,
              bytes.lengthInBytes,
            ),
          ),
        );
        SegmentationStroke stroke(
          SegmentationBrushMode mode,
          List<(double, double)> points,
        ) => SegmentationStroke(
          brushMode: mode,
          points: [for (final (x, y) in points) SegmentationPoint(x: x, y: y)],
        );
        final (x, y) = officialInteractiveReference.point;
        final cat = stroke(SegmentationBrushMode.positive, [(x, y)]);
        final dog = stroke(SegmentationBrushMode.positive, [(0.66, 0.55)]);
        try {
          await task.setImage(VisionImage.fromFile(assets.path('animals.jpg')));
          final file = await task.segment([cat]);
          expect(
            (file.width, file.height),
            (
              officialInteractiveReference.width,
              officialInteractiveReference.height,
            ),
          );
          final gridError = _gridError(file, officialInteractiveReference.grid);
          final meanDelta = (_mean(file) - officialInteractiveReference.mean)
              .abs();
          final foregroundDelta =
              (_foreground(file) - officialInteractiveReference.foreground)
                  .abs();
          expect(gridError, lessThan(0.02));
          expect(meanDelta, lessThan(0.01));
          expect(foregroundDelta, lessThan(0.01));

          // The same image as decoded pixels: the same selection.
          final frame = await loadSample('animals.jpg');
          await task.setImage(frame.image);
          final pixels = await task.segment([cat]);
          final agreement = _agreement(file, pixels);
          expect(agreement, greaterThan(0.99));

          // Strokes add, subtract and enclose, as in Google's references.
          final dogOnly = await task.segment([dog]);
          final both = await task.segment([dog, cat]);
          expect(_foreground(both), greaterThan(_foreground(dogOnly)));
          final negative = await task.segment([
            dog,
            stroke(SegmentationBrushMode.negative, [(0.42, 0.6)]),
          ]);
          expect(
            _foreground(negative),
            lessThanOrEqualTo(_foreground(dogOnly) + 0.001),
          );
          final lasso = await task.segment([
            stroke(SegmentationBrushMode.lasso, [
              (0.52, 0.2),
              (0.78, 0.2),
              (0.78, 0.98),
              (0.52, 0.98),
              (0.52, 0.2),
            ]),
          ]);
          expect(_foreground(lasso), greaterThan(0.01));
          // Undo is a shorter history: the earlier mask again.
          final undone = await task.segment([dog]);
          expect(_agreement(dogOnly, undone), greaterThan(0.999));
          expect(() => task.segment(const []), throwsArgumentError);
          _report('image', {
            'grid_error': gridError,
            'mean_delta': meanDelta,
            'foreground_delta': foregroundDelta,
            'file_pixels_agreement': agreement,
            'foreground': {
              'dog': _foreground(dogOnly),
              'dog_cat': _foreground(both),
              'dog_negative': _foreground(negative),
              'lasso': _foreground(lasso),
            },
          });
        } finally {
          await task.dispose();
        }
        await expectLater(() => task.setImage(blankImage()), throwsStateError);
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'official SDK interactive_segmenter GPU: same selection as CPU',
    (tester) async {
      await tester.runAsync(() async {
        final assets = await GalleryAssets.unpack();
        final bytes = await rootBundle.load(
          'assets/models/interactive_segmentation.task',
        );
        final model = bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
        final (x, y) = officialInteractiveReference.point;
        final history = [
          SegmentationStroke(
            brushMode: SegmentationBrushMode.positive,
            points: [SegmentationPoint(x: x, y: y)],
          ),
        ];
        final masks = <VisionDelegate, SegmentationMask>{};
        for (final delegate in VisionDelegate.values) {
          final InteractiveSegmenter task;
          try {
            task = await InteractiveSegmenter.create(
              InteractiveSegmenterOptions(
                modelBytes: model,
                delegate: delegate,
              ),
            );
          } on InteractiveSegmenterException catch (error) {
            if (delegate == VisionDelegate.cpu || _gpu == 'required') rethrow;
            _report('gpu_unavailable', {'error': error.message});
            return;
          }
          try {
            await task.setImage(
              VisionImage.fromFile(assets.path('animals.jpg')),
            );
            masks[delegate] = await task.segment(history);
          } finally {
            await task.dispose();
          }
        }
        final cpu = masks[VisionDelegate.cpu]!,
            gpu = masks[VisionDelegate.gpu]!;
        final agreement = _agreement(cpu, gpu);
        final gridError = _gridError(gpu, officialInteractiveReference.grid);
        _report('cpu_gpu', {
          'agreement': agreement,
          'gpu_grid_error': gridError,
        });
        expect(agreement, greaterThan(0.97));
      });
    },
    skip: !Platform.isAndroid || _gpu == 'skip',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

/// Mean difference between [mask]'s cell means and Google's.
double _gridError(SegmentationMask mask, List<List<double>> grid) {
  final rows = grid.length, columns = grid.first.length;
  var total = 0.0;
  for (var r = 0; r < rows; r++) {
    final top = r * mask.height ~/ rows, bottom = (r + 1) * mask.height ~/ rows;
    for (var c = 0; c < columns; c++) {
      final left = c * mask.width ~/ columns;
      final right = (c + 1) * mask.width ~/ columns;
      var sum = 0.0;
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          sum += mask.confidence[y * mask.width + x];
        }
      }
      total += (sum / ((bottom - top) * (right - left)) - grid[r][c]).abs();
    }
  }
  return total / (rows * columns);
}

double _mean(SegmentationMask mask) =>
    mask.confidence.fold(0.0, (sum, v) => sum + v) / mask.confidence.length;

/// The share of pixels above 0.5.
double _foreground(SegmentationMask mask) =>
    mask.confidence.where((v) => v > 0.5).length / mask.confidence.length;

/// The share of pixels on the same side of 0.5 in two same-sized masks.
double _agreement(SegmentationMask a, SegmentationMask b) {
  expect((a.width, a.height), (b.width, b.height));
  var same = 0;
  for (var i = 0; i < a.confidence.length; i++) {
    if ((a.confidence[i] > 0.5) == (b.confidence[i] > 0.5)) same++;
  }
  return same / a.confidence.length;
}

void _report(String event, Map<String, Object?> data) {
  // Kept in the device log (logcat, the simulator console) for the record.
  // ignore: avoid_print
  print('SDK_INTERACTIVE ${jsonEncode({'event': event, ...data})}');
}
