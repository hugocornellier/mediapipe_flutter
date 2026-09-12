import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_flutter_vision/models.dart';
import 'package:test/test.dart';

import 'support/vision_fixture.dart';
import 'support/face_reference.dart';

const _fixtures = 'test/fixtures/face_detection';
const _model = 'models/blaze_face_short_range.tflite';

void main() {
  for (final delegate in VisionDelegate.values) {
    group(delegate.name, () => _testDelegate(delegate));
  }
  test('CPU is the default delegate', () {
    expect(FaceDetectorOptions(modelPath: _model).delegate, VisionDelegate.cpu);
  });
}

void _testDelegate(VisionDelegate delegate) {
  final reference = loadFaceReference(
    'face_detection',
    'official${delegate == VisionDelegate.gpu ? '_gpu' : ''}_reference.json',
  );
  final cases = (reference['cases'] as List).cast<Map<String, dynamic>>();
  late FaceDetector detector;

  setUpAll(() async {
    expect(
      sha256.convert(File(_model).readAsBytesSync()).toString(),
      blazeFaceShortRangeSha256,
    );
    expect(reference['model_sha256'], blazeFaceShortRangeSha256);
    expect(reference['delegate'], delegate.name.toUpperCase());
    detector = await FaceDetector.create(
      FaceDetectorOptions(delegate: delegate, modelPath: _model),
    );
  });
  tearDownAll(() async => detector.dispose());
  test(
    'task exposes the selected delegate',
    () => expect(detector.delegate, delegate),
  );

  for (final expected in cases) {
    test('official reference: ${expected['name']}', () async {
      final result = await detector.detectImage(
        fixtureImage(expected),
        rotationDegrees: expected['rotation_degrees'] as int,
      );
      _compare(result, expected);
    });
  }

  test('model bytes produce the same detections', () async {
    final bytes = File(_model).readAsBytesSync();
    final options = FaceDetectorOptions(delegate: delegate, modelBytes: bytes);
    bytes.fillRange(0, bytes.length, 0); // The options own their model data.
    final task = await FaceDetector.create(options);
    try {
      final expected = cases.first;
      _compare(await task.detectImage(fixtureImage(expected)), expected);
    } finally {
      await task.dispose();
    }
  });

  test('queued requests complete before idempotent disposal', () async {
    final task = await FaceDetector.create(
      FaceDetectorOptions(delegate: delegate, modelPath: _model),
    );
    final expected = cases.where((c) => c['name'] == 'rgb').single;
    final requests = [
      for (var i = 0; i < 12; i++) task.detectImage(fixtureImage(expected)),
    ];
    final closing = task.dispose();
    expect(identical(closing, task.dispose()), isTrue);
    await expectLater(
      task.detectImage(fixtureImage(expected)),
      throwsStateError,
    );
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
      _compare(
        await detector.detectImage(fixtureImage(cases.first)),
        cases.first,
      );
    },
  );

  test(
    'invalid model initialization fails promptly without poisoning later tasks',
    () async {
      for (final options in [
        FaceDetectorOptions(
          delegate: delegate,
          modelPath: 'missing-model.tflite',
        ),
        FaceDetectorOptions(delegate: delegate, modelBytes: Uint8List(32)),
      ]) {
        await expectLater(
          FaceDetector.create(options).timeout(const Duration(seconds: 10)),
          throwsA(isA<FaceDetectorException>()),
        );
      }
      final task = await FaceDetector.create(
        FaceDetectorOptions(delegate: delegate, modelPath: _model),
      );
      await task.dispose();
    },
  );

  test(
    'invalid input is rejected before crossing the native boundary',
    () async {
      expect(
        () => FaceDetectorOptions(delegate: delegate),
        throwsArgumentError,
      );
      expect(
        () => FaceDetectorOptions(
          delegate: delegate,
          modelPath: _model,
          modelBytes: Uint8List(1),
        ),
        throwsArgumentError,
      );
      expect(
        () =>
            FaceDetectorOptions(delegate: delegate, modelPath: 'bad\u0000path'),
        throwsArgumentError,
      );
      for (final confidence in [-0.1, 1.1, double.nan, double.infinity]) {
        expect(
          () => FaceDetectorOptions(
            delegate: delegate,
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
        detector.detectImage(fixtureImage(cases.first), rotationDegrees: 45),
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

  test('video sequence matches the official VIDEO-mode reference', () async {
    final reference = loadFaceReference(
      'face_detection',
      'official${delegate == VisionDelegate.gpu ? '_gpu' : ''}_video_reference.json',
    );
    expect(reference['running_mode'], 'VIDEO');
    expect(reference['model_sha256'], blazeFaceShortRangeSha256);
    final video = await FaceDetector.create(
      FaceDetectorOptions(
        delegate: delegate,
        modelPath: _model,
        runningMode: VisionRunningMode.video,
      ),
    );
    final frames = (reference['cases'] as List).cast<Map<String, dynamic>>();
    // Queue the sequence, then dispose immediately: timestamps and results must
    // stay paired, and shutdown must wait for every submitted frame.
    final requests = [
      for (final frame in frames)
        video.detectForVideo(
          fixtureImage(frame),
          timestampMilliseconds: frame['timestamp_ms'] as int,
          rotationDegrees: frame['rotation_degrees'] as int,
        ),
    ];
    final closing = video.dispose();
    final results = await Future.wait(requests);
    await closing;
    for (var i = 0; i < frames.length; i++) {
      _compare(results[i], frames[i]);
      expect(results[i].timestampMilliseconds, frames[i]['timestamp_ms']);
    }
  });

  test(
    'video timestamps and mode mismatches fail without poisoning the task',
    () async {
      final expected = cases.where((c) => c['name'] == 'rgb').single;
      final image = fixtureImage(expected);
      final video = await FaceDetector.create(
        FaceDetectorOptions(
          delegate: delegate,
          modelPath: _model,
          runningMode: VisionRunningMode.video,
        ),
      );
      try {
        await expectLater(video.detectImage(image), throwsStateError);
        await expectLater(
          detector.detectForVideo(image, timestampMilliseconds: 0),
          throwsStateError,
        );
        _compare(
          await video.detectForVideo(image, timestampMilliseconds: 10),
          expected,
        );
        for (final timestamp in [-1, 9, 10, 0x7fffffffffffffff]) {
          await expectLater(
            video.detectForVideo(image, timestampMilliseconds: timestamp),
            throwsArgumentError,
          );
        }
        await expectLater(
          video.detectForVideo(
            image,
            timestampMilliseconds: 11,
            rotationDegrees: 45,
          ),
          throwsArgumentError,
        );
        await expectLater(
          video.detectForVideo(
            VisionImage.fromFile('missing.jpg'),
            timestampMilliseconds: 11,
          ),
          throwsA(isA<FaceDetectorException>()),
        );
        _compare(
          await video.detectForVideo(image, timestampMilliseconds: 12),
          expected,
        );
      } finally {
        await video.dispose();
      }
    },
  );

  for (final format in VisionPixelFormat.values) {
    test(
      'padded ${format.name} camera pixels preserve official detections',
      () async {
        final expected = cases.where((c) => c['name'] == 'rgb').single;
        final rgb = fixtureImage(expected).pixels!;
        final stride = 301 * format.channels + 20;
        final bytes = Uint8List(stride * 209)..fillRange(0, stride * 209, 127);
        for (var y = 0; y < 209; y++) {
          for (var x = 0; x < 301; x++) {
            final source = (y * 301 + x) * 3;
            final target = y * stride + x * format.channels;
            bytes[target] =
                rgb[source + (format == VisionPixelFormat.bgra ? 2 : 0)];
            bytes[target + 1] = rgb[source + 1];
            bytes[target + 2] =
                rgb[source + (format == VisionPixelFormat.bgra ? 0 : 2)];
            if (format.channels == 4) bytes[target + 3] = 255;
          }
        }
        final image = VisionImage.fromPixels(
          pixels: bytes,
          width: 301,
          height: 209,
          format: format,
          bytesPerRow: stride,
        );
        bytes.fillRange(0, bytes.length, 0);
        _compare(await detector.detectImage(image), expected);
      },
    );
  }

  test('invalid camera strides fail before native allocation', () {
    for (final stride in [-1, 0, 3, 0x7fffffffffffffff]) {
      expect(
        () => VisionImage.fromPixels(
          pixels: Uint8List(8),
          width: 2,
          height: 1,
          format: VisionPixelFormat.bgra,
          bytesPerRow: stride,
        ),
        throwsArgumentError,
      );
    }
  });
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
