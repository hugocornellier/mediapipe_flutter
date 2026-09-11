import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_flutter_vision/models.dart';
import 'package:test/test.dart';

const _fixtures = 'test/fixtures/face_detection';
const _model = 'models/blaze_face_short_range.tflite';

void main() {
  final reference =
      jsonDecode(File('$_fixtures/official_reference.json').readAsStringSync())
          as Map<String, dynamic>;
  final cases = (reference['cases'] as List).cast<Map<String, dynamic>>();
  late FaceDetector detector;

  setUpAll(() async {
    expect(
      sha256.convert(File(_model).readAsBytesSync()).toString(),
      blazeFaceShortRangeSha256,
    );
    expect(reference['model_sha256'], blazeFaceShortRangeSha256);
    detector = await FaceDetector.create(
      FaceDetectorOptions(modelPath: _model),
    );
  });
  tearDownAll(() async => detector.dispose());

  for (final expected in cases) {
    test('official reference: ${expected['name']}', () async {
      final result = await detector.detectImage(
        _image(expected),
        rotationDegrees: expected['rotation_degrees'] as int,
      );
      _compare(result, expected);
    });
  }

  test('model bytes produce the same detections', () async {
    final bytes = File(_model).readAsBytesSync();
    final options = FaceDetectorOptions(modelBytes: bytes);
    bytes.fillRange(0, bytes.length, 0); // The options own their model data.
    final task = await FaceDetector.create(options);
    try {
      final expected = cases.first;
      _compare(await task.detectImage(_image(expected)), expected);
    } finally {
      await task.dispose();
    }
  });

  test('queued requests complete before idempotent disposal', () async {
    final task = await FaceDetector.create(
      FaceDetectorOptions(modelPath: _model),
    );
    final expected = cases.where((c) => c['name'] == 'rgb').single;
    final requests = [
      for (var i = 0; i < 12; i++) task.detectImage(_image(expected)),
    ];
    final closing = task.dispose();
    expect(identical(closing, task.dispose()), isTrue);
    await expectLater(task.detectImage(_image(expected)), throwsStateError);
    final results = await Future.wait(requests);
    await closing;
    for (final result in results) {
      _compare(result, expected); // Results remain valid after native teardown.
      expect(() => result.detections.clear(), throwsUnsupportedError);
      expect(
        () => result.detections.single.keypoints.clear(),
        throwsUnsupportedError,
      );
    }
  });

  test(
    'missing image reports a native error and leaves the task usable',
    () async {
      await expectLater(
        detector.detectImage(VisionImage.fromFile('missing-image.jpg')),
        throwsA(
          isA<FaceDetectorException>().having(
            (e) => e.message,
            'diagnostic',
            isNotEmpty,
          ),
        ),
      );
      _compare(await detector.detectImage(_image(cases.first)), cases.first);
    },
  );

  test(
    'invalid model initialization fails promptly without poisoning later tasks',
    () async {
      for (final options in [
        FaceDetectorOptions(modelPath: 'missing-model.tflite'),
        FaceDetectorOptions(modelBytes: Uint8List(32)),
      ]) {
        await expectLater(
          FaceDetector.create(options).timeout(const Duration(seconds: 10)),
          throwsA(isA<FaceDetectorException>()),
        );
      }
      final task = await FaceDetector.create(
        FaceDetectorOptions(modelPath: _model),
      );
      await task.dispose();
    },
  );

  test(
    'invalid input is rejected before crossing the native boundary',
    () async {
      expect(() => FaceDetectorOptions(), throwsArgumentError);
      expect(
        () => FaceDetectorOptions(modelPath: _model, modelBytes: Uint8List(1)),
        throwsArgumentError,
      );
      expect(
        () => FaceDetectorOptions(modelPath: 'bad\u0000path'),
        throwsArgumentError,
      );
      for (final confidence in [-0.1, 1.1, double.nan, double.infinity]) {
        expect(
          () => FaceDetectorOptions(
            modelPath: _model,
            minDetectionConfidence: confidence,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => VisionImage.fromPixels(
          pixels: Uint8List(4),
          width: 1,
          height: 1,
          format: VisionPixelFormat.rgb,
        ),
        throwsArgumentError,
      );
      expect(
        () => VisionImage.fromPixels(
          pixels: Uint8List(0),
          width: 0,
          height: 1,
          format: VisionPixelFormat.rgb,
        ),
        throwsArgumentError,
      );
      // Their product wraps to zero on the VM; individual C-int bounds must
      // reject these dimensions even though the empty byte count would match.
      expect(
        () => VisionImage.fromPixels(
          pixels: Uint8List(0),
          width: 0x100000000,
          height: 0x100000000,
          format: VisionPixelFormat.rgb,
        ),
        throwsArgumentError,
      );
      await expectLater(
        detector.detectImage(_image(cases.first), rotationDegrees: 45),
        throwsArgumentError,
      );
    },
  );

  test('pixel input owns an immutable snapshot', () async {
    final expected = cases.where((c) => c['name'] == 'rgb').single;
    final source = File('$_fixtures/${expected['raw']}').readAsBytesSync();
    final image = VisionImage.fromPixels(
      pixels: source,
      width: 301,
      height: 209,
      format: VisionPixelFormat.rgb,
    );
    source.fillRange(0, source.length, 0);
    expect(() => image.pixels![0] = 0, throwsUnsupportedError);
    _compare(await detector.detectImage(image), expected);
  });
}

VisionImage _image(Map<String, dynamic> expected) {
  if (expected['file'] case final String name) {
    final file = File('$_fixtures/$name');
    expect(
      sha256.convert(file.readAsBytesSync()).toString(),
      expected['sha256'],
    );
    return VisionImage.fromFile(file.path);
  }
  var pixels = Uint8List(640 * 480 * 3);
  var format = VisionPixelFormat.rgb;
  if (expected['raw'] case final String name) {
    pixels = File('$_fixtures/$name').readAsBytesSync();
    expect(sha256.convert(pixels).toString(), expected['sha256']);
    if (expected['name'] == 'rgba') {
      final rgba = Uint8List(301 * 209 * 4);
      for (var i = 0; i < 301 * 209; i++) {
        rgba.setRange(i * 4, i * 4 + 3, pixels, i * 3);
        rgba[i * 4 + 3] = 255;
      }
      pixels = rgba;
      format = VisionPixelFormat.rgba;
    } else if (expected['name'] == 'rgb-rotated') {
      final rotated = Uint8List(pixels.length);
      for (var y = 0; y < 209; y++) {
        for (var x = 0; x < 301; x++) {
          final destination = ((301 - 1 - x) * 209 + y) * 3;
          rotated.setRange(
            destination,
            destination + 3,
            pixels,
            (y * 301 + x) * 3,
          );
        }
      }
      pixels = rotated;
    } else if (expected['name'] == 'rgb-pair') {
      final pair = Uint8List(360 * 209 * 3);
      for (var y = 0; y < 209; y++) {
        for (var face = 0; face < 2; face++) {
          final offset = (y * 360 + face * 180) * 3;
          pair.setRange(offset, offset + 180 * 3, pixels, (y * 301 + 60) * 3);
        }
      }
      pixels = pair;
    }
  }
  return VisionImage.fromPixels(
    pixels: pixels,
    width: expected['width'] as int,
    height: expected['height'] as int,
    format: format,
  );
}

void _compare(FaceDetectorResult actual, Map<String, dynamic> expected) {
  expect(actual.imageWidth, expected['width']);
  expect(actual.imageHeight, expected['height']);
  final faces = (expected['detections'] as List).cast<Map<String, dynamic>>();
  expect(actual.detections, hasLength(faces.length));
  for (var i = 0; i < faces.length; i++) {
    final face = actual.detections[i];
    final box = faces[i]['bounding_box'] as Map<String, dynamic>;
    expect(face.boundingBox.left, closeTo(box['origin_x'] as num, 1));
    expect(face.boundingBox.top, closeTo(box['origin_y'] as num, 1));
    expect(face.boundingBox.width, closeTo(box['width'] as num, 1));
    expect(face.boundingBox.height, closeTo(box['height'] as num, 1));
    final categories = faces[i]['categories'] as List;
    expect(face.categories, hasLength(categories.length));
    for (var j = 0; j < categories.length; j++) {
      final category = face.categories[j];
      final expectedCategory = categories[j] as Map<String, dynamic>;
      expect(category.index, expectedCategory['index']);
      expect(
        category.score,
        closeTo(expectedCategory['score'] as num, 0.00001),
      );
      expect(category.categoryName, expectedCategory['category_name']);
      expect(category.displayName, expectedCategory['display_name']);
    }
    final points = faces[i]['keypoints'] as List;
    expect(face.keypoints, hasLength(points.length));
    for (var j = 0; j < points.length; j++) {
      final point = points[j] as Map<String, dynamic>;
      expect(face.keypoints[j].x, closeTo(point['x'] as num, 0.00001));
      expect(face.keypoints[j].y, closeTo(point['y'] as num, 0.00001));
      expect(face.keypoints[j].label, point['label']);
      // Python exposes 0.0 for missing keypoint confidence; the C API separately
      // exposes has_score=false, represented by null in Dart.
      expect(face.keypoints[j].score ?? 0.0, point['score']);
    }
  }
}
