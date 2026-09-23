import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_flutter_vision/vision_task_backend.dart';
import 'package:mediapipe_gallery/main.dart';

import 'support/official_detection_references.dart';
import 'support/sdk_frames.dart';

/// As in sdk_hand_landmarker_test.dart: `required` fails when the SDK refuses
/// the GPU, `optional` records a refusal at creation, `skip` runs CPU only.
const _gpu = String.fromEnvironment('SDK_GPU', defaultValue: 'optional');

/// Another runtime build and image decoder than the reference's: the same
/// image must still embed to nearly the same direction.
const _crossRuntime = 0.99;

// Image Embedder through Google's official mobile SDKs: iOS through the
// package's Objective-C adapter, Android through
// mediapipe_flutter_vision_android.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'official SDK image_embedder: reference, options, pixels, rotation, region',
    (tester) async {
      await tester.runAsync(() async {
        expect(Platform.isAndroid || Platform.isIOS, isTrue);
        if (Platform.isAndroid) {
          expect(imageEmbedderBackendFactory, isNotNull);
        }
        final assets = await GalleryAssets.unpack();
        final model = await _model();
        final frame = await loadSample('portrait.jpg');
        final references = <VisionDelegate, VisionEmbedding>{};
        for (final delegate in [
          VisionDelegate.cpu,
          if (_gpu != 'skip') VisionDelegate.gpu,
        ]) {
          final ImageEmbedder task;
          try {
            task = await ImageEmbedder.create(
              ImageEmbedderOptions(modelBytes: model, delegate: delegate),
            );
          } on VisionTaskException catch (error) {
            if (delegate == VisionDelegate.cpu || _gpu == 'required') rethrow;
            _report('gpu_unavailable', {'error': error.message});
            continue;
          }
          try {
            final file = _single(
              await task.embedImage(
                VisionImage.fromFile(assets.path('portrait.jpg')),
              ),
            );
            expect(
              file.floatEmbedding,
              hasLength(officialEmbedderReference.length),
            );
            final official = _cosine(
              file.floatEmbedding!,
              officialEmbedderReference,
            );
            expect(official, greaterThan(_crossRuntime));
            final reference = await task.embedImage(frame.image);
            references[delegate] = _single(reference);
            expect(reference.imageWidth, frame.width);
            for (final format in VisionPixelFormat.values) {
              final padded = await task.embedImage(paddedImage(frame, format));
              expect(
                ImageEmbedder.cosineSimilarity(
                  _single(reference),
                  _single(padded),
                ),
                greaterThan(0.99999),
                reason: format.name,
              );
            }
            for (final turn in [90, 180, 270]) {
              final rotated = rotatedImage(frame, (360 - turn) % 360);
              final result = await task.embedImage(
                rotated,
                rotationDegrees: turn,
              );
              expect(
                result.imageWidth,
                turn % 180 == 0 ? frame.width : frame.height,
              );
              // MediaPipe stands the image upright before embedding it.
              expect(
                ImageEmbedder.cosineSimilarity(
                  _single(reference),
                  _single(result),
                ),
                greaterThan(0.95),
                reason: '$turn',
              );
            }
            // A full-frame region is the whole image, which also pins the
            // region's normalized coordinates.
            final whole = await task.embedImage(
              frame.image,
              regionOfInterest: VisionRegionOfInterest(
                left: 0,
                top: 0,
                right: 1,
                bottom: 1,
              ),
            );
            expect(
              ImageEmbedder.cosineSimilarity(
                _single(reference),
                _single(whole),
              ),
              greaterThan(0.9999),
            );
            _report('image', {
              'delegate': delegate.name,
              'official_cosine': official,
              'dimensions': file.floatEmbedding!.length,
            });
          } finally {
            await task.dispose();
          }
          await task.dispose();
          await expectLater(task.embedImage(frame.image), throwsStateError);
        }
        if (references.length == 2) {
          final similarity = ImageEmbedder.cosineSimilarity(
            references[VisionDelegate.cpu]!,
            references[VisionDelegate.gpu]!,
          );
          expect(similarity, greaterThan(_crossRuntime));
          _report('cpu_gpu', {'cosine': similarity});
        }

        // L2 normalization and scalar quantization, as Google's options.
        final normalized = await ImageEmbedder.create(
          ImageEmbedderOptions(modelBytes: model, l2Normalize: true),
        );
        final quantized = await ImageEmbedder.create(
          ImageEmbedderOptions(
            modelBytes: model,
            l2Normalize: true,
            quantize: true,
          ),
        );
        try {
          final unit = _single(await normalized.embedImage(frame.image));
          final norm = math.sqrt(
            unit.floatEmbedding!.fold(0.0, (sum, v) => sum + v * v),
          );
          expect(norm, closeTo(1, 1e-4));
          final bytes = _single(await quantized.embedImage(frame.image));
          expect(bytes.floatEmbedding, isNull);
          expect(
            bytes.quantizedEmbedding,
            hasLength(unit.floatEmbedding!.length),
          );
          final signed = [
            for (final v in bytes.quantizedEmbedding!) v.toSigned(8).toDouble(),
          ];
          final agreement = _cosine(signed, unit.floatEmbedding!);
          expect(agreement, greaterThan(0.99));
          _report('options', {'norm': norm, 'quantized_cosine': agreement});
        } finally {
          await normalized.dispose();
          await quantized.dispose();
        }
        await expectLater(
          ImageEmbedder.create(
            ImageEmbedderOptions(modelBytes: Uint8List.fromList([1, 2, 3])),
          ),
          throwsA(isA<Exception>()),
        );
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'official SDK image_embedder VIDEO: queued frames and timestamps',
    (tester) async {
      await tester.runAsync(() async {
        final frame = await loadSample('portrait.jpg');
        final task = await ImageEmbedder.create(
          ImageEmbedderOptions(
            modelBytes: await _model(),
            runningMode: VisionRunningMode.video,
          ),
        );
        try {
          await expectLater(task.embedImage(frame.image), throwsStateError);
          await expectLater(
            task.embedForVideo(frame.image, timestampMilliseconds: -1),
            throwsArgumentError,
          );
          final queued = await Future.wait([
            task.embedForVideo(frame.image, timestampMilliseconds: 0),
            task.embedForVideo(frame.image, timestampMilliseconds: 33),
          ]);
          expect(queued.map((r) => r.timestampMilliseconds), [0, 33]);
          for (var i = 2; i < 12; i++) {
            final result = await task.embedForVideo(
              frame.image,
              timestampMilliseconds: i * 33,
            );
            expect(result.embeddings, isNotEmpty);
          }
          _report('video', {'frames': 12});
        } finally {
          await task.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

VisionEmbedding _single(ImageEmbedderResult result) {
  expect(result.embeddings, hasLength(1));
  return result.embeddings.single;
}

double _cosine(List<double> a, List<double> b) {
  var dot = 0.0, left = 0.0, right = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    left += a[i] * a[i];
    right += b[i] * b[i];
  }
  return dot / math.sqrt(left) / math.sqrt(right);
}

Future<Uint8List> _model() async {
  final bytes = await rootBundle.load(
    'assets/models/mobilenet_v3_small.tflite',
  );
  return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}

void _report(String event, Map<String, Object?> data) {
  // Kept in the device log (logcat, the simulator console) for the record.
  // ignore: avoid_print
  print('SDK_EMBEDDER ${jsonEncode({'event': event, ...data})}');
}
