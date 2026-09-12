import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_flutter_vision/models.dart';
import 'package:test/test.dart';

import 'support/vision_fixture.dart';

const _model = 'models/face_landmarker.task';
const _fixtures = 'test/fixtures/face_detection';
final _reference =
    jsonDecode(
          File(
            'test/fixtures/face_landmarker/official_reference.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
final _cases = (_reference['cases'] as List).cast<Map<String, dynamic>>();
final _rgb = (_cases.first['frames'] as List)
    .cast<Map<String, dynamic>>()
    .singleWhere((frame) => frame['name'] == 'rgb');

void main() {
  setUpAll(() {
    expect(
      sha256.convert(File(_model).readAsBytesSync()).toString(),
      faceLandmarkerSha256,
    );
    expect(_reference['model_sha256'], faceLandmarkerSha256);
  });

  for (final sequence in _cases) {
    test(
      'official ${sequence['mode']} reference with ${sequence['num_faces']} faces',
      () async {
        final video = sequence['mode'] == 'VIDEO';
        final task = await FaceLandmarker.create(
          FaceLandmarkerOptions(
            modelPath: _model,
            runningMode: video
                ? VisionRunningMode.video
                : VisionRunningMode.image,
            numFaces: sequence['num_faces'] as int,
            outputFaceBlendshapes: true,
            outputFacialTransformationMatrixes: true,
          ),
        );
        final frames = (sequence['frames'] as List)
            .cast<Map<String, dynamic>>();
        final requests = [
          for (final frame in frames)
            video
                ? task.detectForVideo(
                    _image(frame),
                    timestampMilliseconds: frame['timestamp_ms'] as int,
                    rotationDegrees: frame['rotation'] as int,
                  )
                : task.detectImage(
                    _image(frame),
                    rotationDegrees: frame['rotation'] as int,
                  ),
        ];
        final closing = task.dispose();
        expect(identical(closing, task.dispose()), isTrue);
        await expectLater(task.detectImage(_image(_rgb)), throwsStateError);
        final results = await Future.wait(requests);
        await closing;
        for (var i = 0; i < frames.length; i++) {
          _compare(results[i], frames[i]);
        }
        final face = results.first.faceLandmarks.first;
        expect(() => face.clear(), throwsUnsupportedError);
        expect(
          () => results.first.faceLandmarks.clear(),
          throwsUnsupportedError,
        );
        expect(
          () => results.first.faceBlendshapes.first.clear(),
          throwsUnsupportedError,
        );
        expect(
          () => results.first.facialTransformationMatrixes.first.values.clear(),
          throwsUnsupportedError,
        );
      },
    );
  }

  test('model bytes are owned and optional outputs default to empty', () async {
    final bytes = File(_model).readAsBytesSync();
    final options = FaceLandmarkerOptions(modelBytes: bytes);
    bytes.fillRange(0, bytes.length, 0);
    final task = await FaceLandmarker.create(options);
    try {
      final result = await task.detectImage(_image(_rgb));
      _compare(result, {
        ..._rgb,
        'face_blendshapes': [],
        'facial_transformation_matrixes': [],
      });
    } finally {
      await task.dispose();
    }
  });

  test(
    'detector and landmarker coexist in one process with independent lifetimes',
    () async {
      final detector = await FaceDetector.create(
        FaceDetectorOptions(modelPath: 'models/blaze_face_short_range.tflite'),
      );
      final mesh = await FaceLandmarker.create(
        FaceLandmarkerOptions(modelPath: _model),
      );
      try {
        for (var i = 0; i < 3; i++) {
          final results = await Future.wait<Object>([
            detector.detectImage(_image(_rgb)),
            mesh.detectImage(_image(_rgb)),
          ]);
          expect(
            (results[0] as FaceDetectorResult).detections.single.keypoints,
            hasLength(6),
          );
          expect(
            (results[1] as FaceLandmarkerResult).faceLandmarks.single,
            hasLength(478),
          );
        }
        await detector.dispose();
        expect(
          (await mesh.detectImage(_image(_rgb))).faceLandmarks.single,
          hasLength(478),
        );
      } finally {
        await detector.dispose();
        await mesh.dispose();
      }
    },
  );

  for (final format in VisionPixelFormat.values) {
    test(
      'padded ${format.name} camera frames preserve the landmark coordinates',
      () async {
        final rgb = _image(_rgb).pixels!;
        final stride = 301 * format.channels + 20;
        final pixels = Uint8List(stride * 209)..fillRange(0, stride * 209, 127);
        for (var y = 0; y < 209; y++) {
          for (var x = 0; x < 301; x++) {
            final source = (y * 301 + x) * 3;
            final target = y * stride + x * format.channels;
            pixels[target] =
                rgb[source + (format == VisionPixelFormat.bgra ? 2 : 0)];
            pixels[target + 1] = rgb[source + 1];
            pixels[target + 2] =
                rgb[source + (format == VisionPixelFormat.bgra ? 0 : 2)];
            if (format.channels == 4) pixels[target + 3] = 255;
          }
        }
        final task = await FaceLandmarker.create(
          FaceLandmarkerOptions(
            modelPath: _model,
            numFaces: 2,
            outputFaceBlendshapes: true,
            outputFacialTransformationMatrixes: true,
          ),
        );
        try {
          final image = VisionImage.fromPixels(
            pixels: pixels,
            width: 301,
            height: 209,
            format: format,
            bytesPerRow: stride,
          );
          pixels.fillRange(0, pixels.length, 0);
          _compare(await task.detectImage(image), _rgb);
        } finally {
          await task.dispose();
        }
      },
    );
  }

  test(
    'mode, timestamps, rotation and native errors leave video task usable',
    () async {
      final task = await FaceLandmarker.create(
        FaceLandmarkerOptions(
          modelPath: _model,
          runningMode: VisionRunningMode.video,
        ),
      );
      try {
        await expectLater(task.detectImage(_image(_rgb)), throwsStateError);
        await task.detectForVideo(_image(_rgb), timestampMilliseconds: 10);
        for (final timestamp in [-1, 9, 10, 0x7fffffffffffffff]) {
          await expectLater(
            task.detectForVideo(_image(_rgb), timestampMilliseconds: timestamp),
            throwsArgumentError,
          );
        }
        await expectLater(
          task.detectForVideo(
            _image(_rgb),
            timestampMilliseconds: 11,
            rotationDegrees: 45,
          ),
          throwsArgumentError,
        );
        await expectLater(
          task.detectForVideo(
            VisionImage.fromFile('missing.jpg'),
            timestampMilliseconds: 11,
          ),
          throwsA(isA<FaceLandmarkerException>()),
        );
        await expectLater(
          task.detectForVideo(_image(_rgb), timestampMilliseconds: 11),
          throwsArgumentError,
        );
        expect(
          (await task.detectForVideo(
            _image(_rgb),
            timestampMilliseconds: 12,
          )).faceLandmarks.single,
          hasLength(478),
        );
      } finally {
        await task.dispose();
      }
    },
  );

  test(
    'invalid initialization fails promptly; later creation still succeeds',
    () async {
      for (final options in [
        FaceLandmarkerOptions(modelPath: 'missing.task'),
        FaceLandmarkerOptions(modelBytes: Uint8List(32)),
      ]) {
        await expectLater(
          FaceLandmarker.create(options).timeout(const Duration(seconds: 10)),
          throwsA(isA<FaceLandmarkerException>()),
        );
      }
      final task = await FaceLandmarker.create(
        FaceLandmarkerOptions(modelPath: _model),
      );
      try {
        await expectLater(
          task.detectForVideo(_image(_rgb), timestampMilliseconds: 0),
          throwsStateError,
        );
        expect(
          (await task.detectImage(_image(_rgb))).faceLandmarks.single,
          hasLength(478),
        );
      } finally {
        await task.dispose();
      }
    },
  );

  test(
    'options reject malformed model sources, face counts and thresholds',
    () {
      expect(() => FaceLandmarkerOptions(), throwsArgumentError);
      expect(
        () =>
            FaceLandmarkerOptions(modelPath: _model, modelBytes: Uint8List(1)),
        throwsArgumentError,
      );
      expect(
        () => FaceLandmarkerOptions(modelBytes: Uint8List(0)),
        throwsArgumentError,
      );
      expect(
        () => FaceLandmarkerOptions(modelPath: 'bad\u0000path'),
        throwsArgumentError,
      );
      for (final count in [0, -1, 0x80000000]) {
        expect(
          () => FaceLandmarkerOptions(modelPath: _model, numFaces: count),
          throwsArgumentError,
        );
      }
      for (final confidence in [-0.1, 1.1, double.nan, double.infinity]) {
        expect(
          () => FaceLandmarkerOptions(
            modelPath: _model,
            minFaceDetectionConfidence: confidence,
          ),
          throwsArgumentError,
        );
        expect(
          () => FaceLandmarkerOptions(
            modelPath: _model,
            minFacePresenceConfidence: confidence,
          ),
          throwsArgumentError,
        );
        expect(
          () => FaceLandmarkerOptions(
            modelPath: _model,
            minTrackingConfidence: confidence,
          ),
          throwsArgumentError,
        );
      }
    },
  );
}

VisionImage _image(Map<String, dynamic> frame) {
  final name = frame['name'] as String;
  if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
    final manifest =
        jsonDecode(File('$_fixtures/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final entry = (manifest['files'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((file) => file['file'] == name);
    return fixtureImage({...frame, ...entry});
  }
  return fixtureImage({
    ...frame,
    'name': {'rotated': 'rgb-rotated', 'pair': 'rgb-pair'}[name] ?? name,
    if (name != 'blank') 'raw': 'portrait-301x209.rgb',
    'sha256': _reference['raw_sha256'],
  });
}

void _compare(FaceLandmarkerResult actual, Map<String, dynamic> expected) {
  expect(actual.imageWidth, expected['width']);
  expect(actual.imageHeight, expected['height']);
  expect(actual.timestampMilliseconds, expected['timestamp_ms']);
  final faces = expected['face_landmarks'] as List;
  expect(
    actual.faceLandmarks,
    hasLength(faces.length),
    reason: expected['name'] as String,
  );
  for (var i = 0; i < faces.length; i++) {
    final points = faces[i] as List;
    expect(actual.faceLandmarks[i], hasLength(478));
    expect(points, hasLength(478));
    for (var j = 0; j < points.length; j++) {
      final point = points[j] as Map<String, dynamic>;
      final value = actual.faceLandmarks[i][j];
      expect(value.x, closeTo(point['x'] as num, 0.0001));
      expect(value.y, closeTo(point['y'] as num, 0.0001));
      expect(value.z, closeTo(point['z'] as num, 0.0001));
      expect(value.visibility, point['visibility']);
      expect(value.presence, point['presence']);
      expect(value.name, point['name']);
    }
  }
  final expressions = expected['face_blendshapes'] as List;
  expect(actual.faceBlendshapes, hasLength(expressions.length));
  for (var i = 0; i < expressions.length; i++) {
    final categories = expressions[i] as List;
    expect(actual.faceBlendshapes[i], hasLength(52));
    for (var j = 0; j < categories.length; j++) {
      final value = actual.faceBlendshapes[i][j];
      final category = categories[j] as Map<String, dynamic>;
      expect(value.index, category['index']);
      expect(value.score, closeTo(category['score'] as num, 0.002));
      expect(value.categoryName, category['category_name']);
      expect(value.displayName, category['display_name']);
    }
  }
  final matrices = expected['facial_transformation_matrixes'] as List;
  expect(actual.facialTransformationMatrixes, hasLength(matrices.length));
  for (var i = 0; i < matrices.length; i++) {
    final matrix = actual.facialTransformationMatrixes[i];
    expect(matrix.rows, 4);
    expect(matrix.columns, 4);
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 4; column++) {
        // Python exposes row/column indexing; C stores the same data column-major.
        expect(
          matrix.at(row, column),
          closeTo((matrices[i] as List)[row][column] as num, 0.005),
        );
      }
    }
  }
}
