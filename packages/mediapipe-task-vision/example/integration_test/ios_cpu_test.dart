import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late _Fixtures fixtures;
  setUpAll(() async {
    expect(
      Platform.isIOS,
      isTrue,
      reason: 'Run on an iOS simulator, not the host VM.',
    );
    fixtures = await _Fixtures.load();
  });
  tearDownAll(() async => fixtures.directory.delete(recursive: true));

  testWidgets('CPU detection matches every official IMAGE reference', (
    tester,
  ) async {
    final reference = await fixtures.json(
      'face_detection/official_reference.json',
    );
    final task = await FaceDetector.create(
      FaceDetectorOptions(modelBytes: fixtures.detectorModel),
    );
    try {
      expect(task.delegate, VisionDelegate.cpu);
      for (final frame
          in (reference['cases'] as List).cast<Map<String, dynamic>>()) {
        final result = await task.detectImage(
          await fixtures.image(frame),
          rotationDegrees: frame['rotation_degrees'] as int,
        );
        _detectorMatches(result, frame);
      }
    } finally {
      await task.dispose();
    }
  });

  testWidgets('CPU detection matches official VIDEO sequence', (tester) async {
    final reference = await fixtures.json(
      'face_detection/official_video_reference.json',
    );
    final task = await FaceDetector.create(
      FaceDetectorOptions(
        modelBytes: fixtures.detectorModel,
        runningMode: VisionRunningMode.video,
      ),
    );
    try {
      for (final frame
          in (reference['cases'] as List).cast<Map<String, dynamic>>()) {
        final result = await task.detectForVideo(
          await fixtures.image(frame),
          timestampMilliseconds: frame['timestamp_ms'] as int,
          rotationDegrees: frame['rotation_degrees'] as int,
        );
        expect(result.timestampMilliseconds, frame['timestamp_ms']);
        _detectorMatches(result, frame);
      }
    } finally {
      await task.dispose();
    }
  });

  for (final configuration in [
    (VisionRunningMode.image, 2),
    (VisionRunningMode.video, 1),
    (VisionRunningMode.video, 2),
  ]) {
    testWidgets(
      'CPU ${configuration.$1.name} mesh matches official reference with ${configuration.$2} faces',
      (tester) async {
        final reference = await fixtures.json(
          'face_landmarker/official_reference.json',
        );
        final sequence = (reference['cases'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere(
              (value) =>
                  value['mode'] == configuration.$1.name.toUpperCase() &&
                  value['num_faces'] == configuration.$2,
            );
        final task = await FaceLandmarker.create(
          FaceLandmarkerOptions(
            modelBytes: fixtures.meshModel,
            runningMode: configuration.$1,
            numFaces: configuration.$2,
            outputFaceBlendshapes: true,
            outputFacialTransformationMatrixes: true,
          ),
        );
        try {
          for (final frame
              in (sequence['frames'] as List).cast<Map<String, dynamic>>()) {
            final image = await fixtures.image(frame);
            final result = configuration.$1 == VisionRunningMode.video
                ? await task.detectForVideo(
                    image,
                    timestampMilliseconds: frame['timestamp_ms'] as int,
                    rotationDegrees: frame['rotation'] as int,
                  )
                : await task.detectImage(
                    image,
                    rotationDegrees: frame['rotation'] as int,
                  );
            _meshMatches(result, frame);
          }
        } finally {
          await task.dispose();
        }
      },
    );
  }

  testWidgets('padded RGB, RGBA and BGRA preserve CPU task results together', (
    tester,
  ) async {
    final detectionReference = await fixtures.json(
      'face_detection/official_reference.json',
    );
    final expectedDetection = (detectionReference['cases'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((frame) => frame['name'] == 'rgb');
    final meshReference = await fixtures.json(
      'face_landmarker/official_reference.json',
    );
    final sequence = (meshReference['cases'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((value) => value['mode'] == 'IMAGE');
    final expectedMesh = (sequence['frames'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((frame) => frame['name'] == 'rgb');
    final detector = await FaceDetector.create(
      FaceDetectorOptions(modelBytes: fixtures.detectorModel),
    );
    final mesh = await FaceLandmarker.create(
      FaceLandmarkerOptions(
        modelBytes: fixtures.meshModel,
        numFaces: 2,
        outputFaceBlendshapes: true,
        outputFacialTransformationMatrixes: true,
      ),
    );
    try {
      for (final format in VisionPixelFormat.values) {
        for (final padding in [1, 64]) {
          final stride = 301 * format.channels + padding;
          final pixels = Uint8List(stride * 209)
            ..fillRange(0, stride * 209, 211);
          for (var y = 0; y < 209; y++) {
            for (var x = 0; x < 301; x++) {
              final src = (y * 301 + x) * 3;
              final dst = y * stride + x * format.channels;
              pixels[dst] = fixtures
                  .rgb[src + (format == VisionPixelFormat.bgra ? 2 : 0)];
              pixels[dst + 1] = fixtures.rgb[src + 1];
              pixels[dst + 2] = fixtures
                  .rgb[src + (format == VisionPixelFormat.bgra ? 0 : 2)];
              if (format.channels == 4) pixels[dst + 3] = 255;
            }
          }
          final image = VisionImage.fromPixels(
            pixels: pixels,
            width: 301,
            height: 209,
            bytesPerRow: stride,
            format: format,
          );
          // Both libraries coexist, with independent worker and native lifetimes.
          final pendingDetection = detector.detectImage(image);
          final pendingMesh = mesh.detectImage(image);
          _detectorMatches(await pendingDetection, expectedDetection);
          _meshMatches(await pendingMesh, expectedMesh);
        }
      }
    } finally {
      await detector.dispose();
      await mesh.dispose();
    }
  });

  testWidgets('GPU requests fail explicitly and leave CPU creation usable', (
    tester,
  ) async {
    await expectLater(
      FaceDetector.create(
        FaceDetectorOptions(
          modelBytes: fixtures.detectorModel,
          delegate: VisionDelegate.gpu,
        ),
      ),
      throwsA(
        isA<FaceDetectorException>().having(
          (e) => e.message,
          'message',
          contains('CPU only'),
        ),
      ),
    );
    await expectLater(
      FaceLandmarker.create(
        FaceLandmarkerOptions(
          modelBytes: fixtures.meshModel,
          delegate: VisionDelegate.gpu,
        ),
      ),
      throwsA(
        isA<FaceLandmarkerException>().having(
          (e) => e.message,
          'message',
          contains('CPU only'),
        ),
      ),
    );
    final task = await FaceLandmarker.create(
      FaceLandmarkerOptions(modelBytes: fixtures.meshModel),
    );
    try {
      expect(
        (await task.detectImage(fixtures.portrait)).faceLandmarks.single,
        hasLength(478),
      );
    } finally {
      await task.dispose();
    }
  });

  testWidgets(
    'queued video frames drain before disposal and errors do not poison CPU inference',
    (tester) async {
      final task = await FaceLandmarker.create(
        FaceLandmarkerOptions(
          modelBytes: fixtures.meshModel,
          runningMode: VisionRunningMode.video,
        ),
      );
      try {
        await expectLater(
          task.detectImage(fixtures.portrait),
          throwsStateError,
        );
        await expectLater(
          task.detectForVideo(
            VisionImage.fromFile('${fixtures.directory.path}/missing.jpg'),
            timestampMilliseconds: 0,
          ),
          throwsA(isA<FaceLandmarkerException>()),
        );
        final frames = [
          for (var i = 1; i <= 6; i++)
            task.detectForVideo(
              fixtures.portrait,
              timestampMilliseconds: i * 33,
            ),
        ];
        final closing = task.dispose();
        expect(identical(closing, task.dispose()), isTrue);
        final results = await Future.wait(frames);
        await closing;
        expect(results.map((r) => r.timestampMilliseconds), [
          33,
          66,
          99,
          132,
          165,
          198,
        ]);
        for (final result in results) {
          expect(result.faceLandmarks.single, hasLength(478));
          expect(result.faceBlendshapes, isEmpty);
          expect(result.facialTransformationMatrixes, isEmpty);
        }
        await expectLater(
          task.detectForVideo(fixtures.portrait, timestampMilliseconds: 231),
          throwsStateError,
        );
      } finally {
        await task.dispose();
      }
    },
  );
}

class _Fixtures {
  _Fixtures(this.directory, this.detectorModel, this.meshModel, this.rgb);
  final Directory directory;
  final Uint8List detectorModel;
  final Uint8List meshModel;
  final Uint8List rgb;

  static Future<Uint8List> bytes(String name) async {
    final data = await rootBundle.load(name);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<_Fixtures> load() async {
    final detector = await bytes('assets/blaze_face_short_range.tflite');
    final mesh = await bytes('assets/face_landmarker.task');
    final rgb = await bytes(
      'assets/fixtures/face_detection/portrait-301x209.rgb',
    );
    expect(
      sha256.convert(detector).toString(),
      'b4578f35940bf5a1a655214a1cce5cab13eba73c1297cd78e1a04c2380b0152f',
    );
    expect(
      sha256.convert(mesh).toString(),
      '64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff',
    );
    expect(
      sha256.convert(rgb).toString(),
      '242611c8ea93118b4196bf24ed2b4dfe81dda22f57c91104b8ad233c9e921c77',
    );
    return _Fixtures(
      await Directory.systemTemp.createTemp('mediapipe-ios-test-'),
      detector,
      mesh,
      rgb,
    );
  }

  Future<Map<String, dynamic>> json(String name) async =>
      jsonDecode(await rootBundle.loadString('assets/fixtures/$name'))
          as Map<String, dynamic>;

  VisionImage get portrait => VisionImage.fromPixels(
    pixels: rgb,
    width: 301,
    height: 209,
    format: VisionPixelFormat.rgb,
  );

  Future<VisionImage> image(Map<String, dynamic> frame) async {
    final name = frame['name'] as String;
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      final data = await bytes('assets/fixtures/face_detection/$name');
      final manifest = await json('face_detection/manifest.json');
      final fileInfo = (manifest['files'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((file) => file['file'] == name);
      expect(sha256.convert(data).toString(), fileInfo['sha256']);
      final file = File('${directory.path}/$name');
      await file.writeAsBytes(data);
      return VisionImage.fromFile(file.path);
    }
    final width = frame['width'] as int;
    final height = frame['height'] as int;
    var pixels = name == 'blank' ? Uint8List(width * height * 3) : rgb;
    var format = VisionPixelFormat.rgb;
    if (name == 'rgba') {
      format = VisionPixelFormat.rgba;
      pixels = Uint8List(301 * 209 * 4);
      for (var i = 0; i < 301 * 209; i++) {
        pixels.setRange(i * 4, i * 4 + 3, rgb, i * 3);
        pixels[i * 4 + 3] = 255;
      }
    } else if (name == 'rotated' || name == 'rgb-rotated') {
      pixels = Uint8List(rgb.length);
      for (var y = 0; y < 209; y++) {
        for (var x = 0; x < 301; x++) {
          final dst = ((301 - 1 - x) * 209 + y) * 3;
          pixels.setRange(dst, dst + 3, rgb, (y * 301 + x) * 3);
        }
      }
    } else if (name == 'pair' || name == 'rgb-pair') {
      pixels = Uint8List(360 * 209 * 3);
      for (var y = 0; y < 209; y++) {
        for (var face = 0; face < 2; face++) {
          final dst = (y * 360 + face * 180) * 3;
          pixels.setRange(dst, dst + 180 * 3, rgb, (y * 301 + 60) * 3);
        }
      }
    }
    return VisionImage.fromPixels(
      pixels: pixels,
      width: width,
      height: height,
      format: format,
    );
  }
}

void _detectorMatches(
  FaceDetectorResult actual,
  Map<String, dynamic> expected,
) {
  expect(actual.imageWidth, expected['width']);
  expect(actual.imageHeight, expected['height']);
  final faces = expected['detections'] as List;
  expect(
    actual.detections,
    hasLength(faces.length),
    reason: '${expected['name']}',
  );
  for (var i = 0; i < faces.length; i++) {
    final face = faces[i] as Map<String, dynamic>;
    final box = face['bounding_box'] as Map<String, dynamic>;
    final value = actual.detections[i];
    expect(value.boundingBox.left, closeTo(box['origin_x'] as num, 1));
    expect(value.boundingBox.top, closeTo(box['origin_y'] as num, 1));
    expect(value.boundingBox.width, closeTo(box['width'] as num, 1));
    expect(value.boundingBox.height, closeTo(box['height'] as num, 1));
    final categories = face['categories'] as List;
    expect(value.categories, hasLength(categories.length));
    for (var j = 0; j < categories.length; j++) {
      final category = categories[j] as Map<String, dynamic>;
      expect(value.categories[j].index, category['index']);
      expect(
        value.categories[j].score,
        closeTo(category['score'] as num, .00001),
      );
      expect(value.categories[j].categoryName, category['category_name']);
      expect(value.categories[j].displayName, category['display_name']);
    }
    final points = face['keypoints'] as List;
    expect(value.keypoints, hasLength(points.length));
    for (var j = 0; j < points.length; j++) {
      expect(value.keypoints[j].x, closeTo(points[j]['x'] as num, .00001));
      expect(value.keypoints[j].y, closeTo(points[j]['y'] as num, .00001));
      expect(value.keypoints[j].label, points[j]['label']);
      expect(value.keypoints[j].score ?? 0.0, points[j]['score']);
    }
  }
}

void _meshMatches(FaceLandmarkerResult actual, Map<String, dynamic> expected) {
  expect(actual.imageWidth, expected['width']);
  expect(actual.imageHeight, expected['height']);
  expect(actual.timestampMilliseconds, expected['timestamp_ms']);
  final faces = expected['face_landmarks'] as List;
  expect(
    actual.faceLandmarks,
    hasLength(faces.length),
    reason: '${expected['name']}',
  );
  for (var i = 0; i < faces.length; i++) {
    final points = faces[i] as List;
    expect(actual.faceLandmarks[i], hasLength(478));
    expect(points, hasLength(478));
    for (var j = 0; j < points.length; j++) {
      final value = actual.faceLandmarks[i][j];
      expect(value.x, closeTo(points[j]['x'] as num, .0001));
      expect(value.y, closeTo(points[j]['y'] as num, .0001));
      expect(value.z, closeTo(points[j]['z'] as num, .0001));
      expect(value.visibility, points[j]['visibility']);
      expect(value.presence, points[j]['presence']);
      expect(value.name, points[j]['name']);
    }
  }
  final expressions = expected['face_blendshapes'] as List;
  expect(actual.faceBlendshapes, hasLength(expressions.length));
  for (var i = 0; i < expressions.length; i++) {
    expect(actual.faceBlendshapes[i], hasLength(52));
    for (var j = 0; j < (expressions[i] as List).length; j++) {
      final category = expressions[i][j];
      final value = actual.faceBlendshapes[i][j];
      expect(value.index, category['index']);
      expect(value.score, closeTo(category['score'] as num, .002));
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
        expect(
          matrix.at(row, column),
          closeTo(matrices[i][row][column] as num, .005),
        );
      }
    }
  }
}
