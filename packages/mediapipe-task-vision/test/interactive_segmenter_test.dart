import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_flutter_vision/models.dart';
import 'package:mediapipe_flutter_vision/third_party/mediapipe/interactive_segmenter_bindings.dart'
    as abi;
import 'package:test/test.dart';

const fixtures = 'test/fixtures/interactive_segmentation';
const model = 'models/interactive_segmentation.task';
late Map<String, dynamic> reference;
late Uint8List rgb;

List<SegmentationStroke> strokes(Map<String, dynamic> entry) => [
  for (final dynamic stroke in entry['strokes'])
    SegmentationStroke(
      brushMode: SegmentationBrushMode.values.byName(
        stroke['brush_mode'] as String,
      ),
      points: [
        for (final dynamic point in stroke['points'])
          SegmentationPoint(
            x: (point[0] as num).toDouble(),
            y: (point[1] as num).toDouble(),
          ),
      ],
      isCompleted: stroke['is_completed'] as bool,
    ),
];

VisionImage input(String kind, {int padding = 0, bool bgra = false}) {
  if (kind == 'file')
    return VisionImage.fromFile('$fixtures/cats_and_dogs.jpg');
  final width = reference['raw']['width'] as int;
  final height = reference['raw']['height'] as int;
  final channels = kind == 'rgba' || bgra ? 4 : 3;
  final stride = width * channels + padding;
  final bytes = Uint8List(height * stride)..fillRange(0, height * stride, 197);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final source = (y * width + x) * 3;
      final target = y * stride + x * channels;
      bytes[target] = kind == 'blank' ? 0 : rgb[source + (bgra ? 2 : 0)];
      bytes[target + 1] = kind == 'blank' ? 0 : rgb[source + 1];
      bytes[target + 2] = kind == 'blank' ? 0 : rgb[source + (bgra ? 0 : 2)];
      if (channels == 4) bytes[target + 3] = 255;
    }
  }
  return VisionImage.fromPixels(
    pixels: bytes,
    width: width,
    height: height,
    format: bgra
        ? VisionPixelFormat.bgra
        : channels == 4
        ? VisionPixelFormat.rgba
        : VisionPixelFormat.rgb,
    bytesPerRow: stride,
  );
}

void compare(SegmentationMask mask, Map<String, dynamic> entry) {
  expect(mask.width, entry['width']);
  expect(mask.height, entry['height']);
  final bytes = Uint8List.fromList(
    gzip.decode(File('$fixtures/${entry['mask']}').readAsBytesSync()),
  );
  expect(sha256.convert(bytes).toString(), entry['sha256']);
  final expected = ByteData.sublistView(bytes);
  expect(mask.confidence.length * 4, bytes.length);
  var maximum = 0.0;
  for (var i = 0; i < mask.confidence.length; i++) {
    final value = mask.confidence[i];
    expect(value.isFinite, isTrue, reason: 'nonfinite pixel $i');
    maximum = math.max(
      maximum,
      (value - expected.getFloat32(i * 4, Endian.little)).abs(),
    );
  }
  expect(
    maximum,
    lessThanOrEqualTo(1e-6),
    reason: '${entry['name']} maximum pixel error',
  );
}

void main() {
  setUpAll(() {
    reference =
        jsonDecode(File('$fixtures/official_reference.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(
      sha256.convert(File(model).readAsBytesSync()).toString(),
      interactiveSegmenterModelSha256,
    );
    expect(
      sha256
          .convert(File('$fixtures/cats_and_dogs.jpg').readAsBytesSync())
          .toString(),
      reference['image']['sha256'],
    );
    rgb = File('$fixtures/animals-299x150.rgb').readAsBytesSync();
    expect(sha256.convert(rgb).toString(), reference['raw']['sha256']);
  });

  test(
    'stateful CPU masks match all official Python reference pixels',
    () async {
      final task = await InteractiveSegmenter.create(
        InteractiveSegmenterOptions(modelPath: model),
      );
      addTearDown(task.dispose);
      SegmentationMask? retained;
      Map<String, dynamic>? retainedCase;
      for (final dynamic value in reference['cases']) {
        final entry = value as Map<String, dynamic>;
        if (entry['set_image'] as bool)
          await task.setImage(input(entry['input'] as String));
        final result = await task.segment(strokes(entry));
        compare(result, entry);
        retained ??= result;
        retainedCase ??= entry;
      }
      await task.dispose();
      compare(retained!, retainedCase!);
      expect(() => retained!.confidence[0] = 0, throwsUnsupportedError);
    },
  );

  test(
    'padded RGB, RGBA and BGRA match official masks with model bytes',
    () async {
      final task = await InteractiveSegmenter.create(
        InteractiveSegmenterOptions(modelBytes: File(model).readAsBytesSync()),
      );
      addTearDown(task.dispose);
      final entry =
          (reference['cases'] as List).firstWhere(
                (dynamic c) => c['name'] == 'raw-dog',
              )
              as Map<String, dynamic>;
      for (final kind in ['rgb', 'rgba', 'bgra']) {
        for (final padding in [1, 64]) {
          await task.setImage(
            input(
              kind == 'bgra' ? 'rgba' : kind,
              padding: padding,
              bgra: kind == 'bgra',
            ),
          );
          compare(await task.segment(strokes(entry)), entry);
        }
      }
    },
  );

  test(
    'invalid requests preserve the session and queued calls drain on disposal',
    () async {
      final task = await InteractiveSegmenter.create(
        InteractiveSegmenterOptions(modelPath: model),
      );
      addTearDown(task.dispose);
      final entry = (reference['cases'] as List)[1] as Map<String, dynamic>;
      final history = strokes(entry);
      await expectLater(
        task.segment(history),
        throwsA(isA<InteractiveSegmenterException>()),
      );
      await task.setImage(input('rgb'));
      await expectLater(task.segment([]), throwsArgumentError);
      await expectLater(
        task.setImage(VisionImage.fromFile('missing-segmenter-image.png')),
        throwsA(isA<InteractiveSegmenterException>()),
      );
      compare(await task.segment(history), entry);
      // Snapshot lists when submitted; mutations cannot change queued native work.
      final mutable = List<SegmentationStroke>.of(history);
      final pending = task.segment(mutable);
      mutable.clear();
      final reset = task.setImage(input('rgb'));
      final more = [for (var i = 0; i < 3; i++) task.segment(history)];
      final closing = task.dispose();
      expect(identical(closing, task.dispose()), isTrue);
      await expectLater(task.segment(history), throwsStateError);
      await expectLater(task.setImage(input('rgb')), throwsStateError);
      compare(await pending, entry);
      await reset;
      for (final result in await Future.wait(more)) {
        compare(result, entry);
      }
      await closing;
    },
  );

  test(
    'face CPU and Metal runtimes coexist with the official segmenter',
    () async {
      final task = await InteractiveSegmenter.create(
        InteractiveSegmenterOptions(modelPath: model),
      );
      addTearDown(task.dispose);
      final entry = (reference['cases'] as List)[1] as Map<String, dynamic>;
      for (final delegate in VisionDelegate.values) {
        final detector = await FaceDetector.create(
          FaceDetectorOptions(
            modelPath: 'models/blaze_face_short_range.tflite',
            delegate: delegate,
          ),
        );
        final mesh = await FaceLandmarker.create(
          FaceLandmarkerOptions(
            modelPath: 'models/face_landmarker.task',
            delegate: delegate,
          ),
        );
        try {
          await task.setImage(input('rgb'));
          final pending = task.segment(strokes(entry));
          final portrait = VisionImage.fromFile(
            'test/fixtures/face_detection/landmark-ex1.jpg',
          );
          expect((await detector.detectImage(portrait)).detections.length, 1);
          expect(
            (await mesh.detectImage(portrait)).faceLandmarks.single.length,
            478,
          );
          compare(await pending, entry);
        } finally {
          await detector.dispose();
          await mesh.dispose();
        }
      }
    },
  );

  test(
    'unsupported GPU and corrupt models fail without disabling later CPU use',
    () async {
      await expectLater(
        InteractiveSegmenter.create(
          InteractiveSegmenterOptions(
            modelPath: model,
            delegate: VisionDelegate.gpu,
          ),
        ),
        throwsA(
          isA<InteractiveSegmenterException>().having(
            (e) => e.message,
            'message',
            contains('CPU only'),
          ),
        ),
      );
      await expectLater(
        InteractiveSegmenter.create(
          InteractiveSegmenterOptions(
            modelBytes: Uint8List.fromList([1, 2, 3]),
          ),
        ),
        throwsA(isA<InteractiveSegmenterException>()),
      );
      final task = await InteractiveSegmenter.create(
        InteractiveSegmenterOptions(modelPath: model),
      );
      addTearDown(task.dispose);
      final entry = (reference['cases'] as List)[1] as Map<String, dynamic>;
      await task.setImage(input('rgb'));
      compare(await task.segment(strokes(entry)), entry);
    },
  );

  test('stroke validation and ownership', () {
    expect(() => InteractiveSegmenterOptions(), throwsArgumentError);
    expect(
      () => InteractiveSegmenterOptions(
        modelPath: model,
        modelBytes: Uint8List(1),
      ),
      throwsArgumentError,
    );
    expect(() => SegmentationPoint(x: double.nan, y: .5), throwsArgumentError);
    expect(() => SegmentationPoint(x: 1.1, y: .5), throwsArgumentError);
    expect(
      () => SegmentationStroke(
        brushMode: SegmentationBrushMode.positive,
        points: [],
      ),
      throwsArgumentError,
    );
    final points = [SegmentationPoint(x: .5, y: .5)];
    final stroke = SegmentationStroke(
      brushMode: SegmentationBrushMode.positive,
      points: points,
    );
    points.clear();
    expect(stroke.points.length, 1);
    expect(() => stroke.points.clear(), throwsUnsupportedError);
    expect(
      () => SegmentationStroke(
        brushMode: SegmentationBrushMode.lasso,
        points: stroke.points,
      ),
      throwsArgumentError,
    );
  });

  test(
    'Dart ABI matches the official Python ctypes sizes and field offsets',
    () {
      final sizes = {
        'MpBaseOptionsC': sizeOf<abi.MpBaseOptions>(),
        'InteractiveSegmenterOptionsC':
            sizeOf<abi.MpInteractiveSegmenterOptions>(),
        'MpStrokePointC': sizeOf<abi.MpStrokePoint>(),
        'MpStrokeC': sizeOf<abi.MpStroke>(),
        'MpStrokesC': sizeOf<abi.MpStrokes>(),
      };
      for (final entry in sizes.entries) {
        expect(entry.value, reference['abi'][entry.key]['size']);
      }
      using((arena) {
        final base = arena<abi.MpBaseOptions>();
        base.ref
          ..modelAssetBuffer = Pointer.fromAddress(11)
          ..modelAssetBufferCount = 12
          ..modelAssetPath = Pointer.fromAddress(13)
          ..fileDescriptor = 14
          ..delegate = 15
          ..hostEnvironment = 16
          ..hostSystem = 17
          ..hostVersion = Pointer.fromAddress(18)
          ..caBundlePath = Pointer.fromAddress(19)
          ..appId = Pointer.fromAddress(20)
          ..appVersion = Pointer.fromAddress(21);
        final data = ByteData.sublistView(
          base.cast<Uint8>().asTypedList(sizeOf<abi.MpBaseOptions>()),
        );
        final offsets =
            reference['abi']['MpBaseOptionsC']['offsets']
                as Map<String, dynamic>;
        var expected = 11;
        for (final entry in offsets.entries) {
          expect(data.getUint32(entry.value as int, Endian.host), expected++);
        }
        final stroke = arena<abi.MpStroke>();
        stroke.ref
          ..brushMode = 3
          ..points = Pointer.fromAddress(123)
          ..pointsCount = 9
          ..isCompleted = true;
        final bytes = ByteData.sublistView(
          stroke.cast<Uint8>().asTypedList(sizeOf<abi.MpStroke>()),
        );
        final fields = reference['abi']['MpStrokeC']['offsets'];
        expect(bytes.getInt32(fields['brush_mode'] as int, Endian.host), 3);
        expect(bytes.getUint64(fields['points'] as int, Endian.host), 123);
        expect(bytes.getUint32(fields['points_count'] as int, Endian.host), 9);
        expect(bytes.getUint8(fields['is_completed'] as int), 1);
      });
    },
  );
}
