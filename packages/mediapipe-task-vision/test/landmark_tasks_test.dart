import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_flutter_vision/models.dart';
import 'package:test/test.dart';
import 'support/face_reference.dart';

const _fixtures = 'test/fixtures/landmark_tasks';
const _models = {
  'hand': ('models/hand_landmarker.task', handLandmarkerSha256),
  'gesture': ('models/gesture_recognizer.task', gestureRecognizerSha256),
  'pose': ('models/pose_landmarker_lite.task', poseLandmarkerLiteSha256),
  'holistic': ('models/holistic_landmarker.task', holisticLandmarkerSha256),
};
typedef _Task = (
  Future<Map<String, dynamic>> Function(VisionImage, int, int?),
  Future<void> Function(),
);
// These tasks are validated against the official wheel that ships the same
// native library on Linux and Windows. macOS loads our source build, whose CPU
// results still differ from the official outputs; see upstream-issues.md
// UP-004. Creating a task there fails closed, so the comparisons cannot run.
final _unvalidatedHost =
    Platform.isMacOS &&
        Platform.environment['MEDIAPIPE_OFFICIAL_MACOS_LANDMARK_RUNTIME'] != '1'
    ? 'macOS source-build CPU output is unvalidated; see UP-004'
    : null;
final _selectedTasks =
    switch (Platform.environment['MEDIAPIPE_LANDMARK_TASKS']) {
      final value? => value.split(',').toSet(),
      null => _models.keys.toSet(),
    };

void main() {
  final reference = loadFaceReference(
    'landmark_tasks',
    'official_reference.json',
  );
  final cases = (reference['cases'] as List).cast<Map<String, dynamic>>();
  setUpAll(() {
    for (final (name, row)
        in _models.entries
            .where((entry) => _selectedTasks.contains(entry.key))
            .map((e) => (e.key, e.value))) {
      expect(sha256.convert(File(row.$1).readAsBytesSync()).toString(), row.$2);
      expect(reference['models'][name], row.$2);
    }
  });
  tearDownAll(() {
    for (final task in _selectedTasks) {
      reportReferenceDeltas(task);
    }
  });
  for (final expected in cases.where(
    (c) => c['timestamp_ms'] == null && _selectedTasks.contains(c['task']),
  )) {
    test(
      'official ${expected['task']} / ${expected['input']} / ${expected['file']} / ${expected['options']}',
      () async {
        final (process, close) = await _create(expected);
        try {
          _compare(
            await process(
              _image(expected),
              expected['rotation_degrees'] as int,
              null,
            ),
            expected['result'],
            expected['task'] as String,
          );
        } finally {
          await close();
        }
      },
      skip: _unvalidatedHost,
    );
  }
  for (final name in _models.keys.where(_selectedTasks.contains)) {
    test(
      '$name video matches tracked and empty frames through queued disposal',
      () async {
        final frames = cases
            .where(
              (c) =>
                  c['task'] == name &&
                  c['timestamp_ms'] != null &&
                  (c['options'] as Map)['min_hand_landmarks_confidence'] ==
                      null,
            )
            .toList();
        final (process, close) = await _create(frames.first);
        final requests = [
          for (final frame in frames)
            process(_image(frame), 0, frame['timestamp_ms'] as int),
        ];
        final closing = close();
        expect(identical(closing, close()), isTrue);
        await expectLater(
          process(_image(frames.first), 0, 100),
          throwsStateError,
        );
        final results = await Future.wait(requests);
        await closing;
        for (var i = 0; i < frames.length; i++) {
          _compare(results[i], frames[i]['result'], name);
        }
      },
      skip: _unvalidatedHost,
    );
    test(
      '$name native input/model errors leave later inference usable',
      () async {
        final expected = cases.firstWhere(
          (c) => c['task'] == name && c['input'] == 'file',
        );
        final (process, close) = await _create(expected);
        try {
          await expectLater(
            process(VisionImage.fromFile('missing-image.jpg'), 0, null),
            throwsA(isA<VisionTaskException>()),
          );
          _compare(
            await process(_image(expected), 0, null),
            expected['result'],
            name,
          );
        } finally {
          await close();
        }
        await expectLater(
          _create(
            expected,
            modelBytes: Uint8List(32),
          ).timeout(const Duration(seconds: 10)),
          throwsA(isA<VisionTaskException>()),
        );
        final (_, validClose) = await _create(expected);
        await validClose();
      },
      skip: _unvalidatedHost,
    );
  }
  test(
    'invalid model tracking and classification options fail before native calls',
    () {
      expect(
        () => HandLandmarkerOptions(modelPath: 'model', numHands: 0),
        throwsArgumentError,
      );
      expect(
        () => PoseLandmarkerOptions(modelPath: 'model', numPoses: 0x80000000),
        throwsArgumentError,
      );
      expect(
        () => GestureRecognizerOptions(
          modelPath: 'model',
          minHandDetectionConfidence: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => HolisticLandmarkerOptions(
          modelPath: 'model',
          minPosePresenceConfidence: 1.1,
        ),
        throwsArgumentError,
      );
      expect(
        () => GestureClassifierOptions(
          categoryAllowlist: ['a'],
          categoryDenylist: ['b'],
        ),
        throwsArgumentError,
      );
      expect(
        () => GestureClassifierOptions(displayNamesLocale: 'en\u0000US'),
        throwsArgumentError,
      );
    },
  );
}

VisionImage _image(Map<String, dynamic> expected) {
  if (expected['input'] == 'file') {
    final file = File('$_fixtures/${expected['file']}');
    expect(
      sha256.convert(file.readAsBytesSync()).toString(),
      expected['sha256'],
    );
    return VisionImage.fromFile(file.path);
  }
  var pixels = File('$_fixtures/${expected['raw']}').readAsBytesSync();
  expect(sha256.convert(pixels).toString(), expected['raw_sha256']);
  final width = expected['width'] as int;
  final height = expected['height'] as int;
  var format = VisionPixelFormat.rgb;
  if (expected['input'] == 'blank') {
    pixels = Uint8List(width * height * 3);
  } else if (expected['input'] == 'rgba') {
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      rgba.setRange(i * 4, i * 4 + 3, pixels, i * 3);
      rgba[i * 4 + 3] = 255;
    }
    pixels = rgba;
    format = VisionPixelFormat.rgba;
  } else if (expected['input'] == 'rotated') {
    final rotated = Uint8List(pixels.length);
    final oldWidth = height;
    final oldHeight = width;
    for (var y = 0; y < oldHeight; y++) {
      for (var x = 0; x < oldWidth; x++) {
        final output = ((oldWidth - 1 - x) * oldHeight + y) * 3;
        rotated.setRange(output, output + 3, pixels, (y * oldWidth + x) * 3);
      }
    }
    pixels = rotated;
  }
  return VisionImage.fromPixels(
    pixels: pixels,
    width: width,
    height: height,
    format: format,
  );
}

Future<_Task> _create(
  Map<String, dynamic> expected, {
  Uint8List? modelBytes,
}) async {
  final options = expected['options'] as Map<String, dynamic>;
  final name = expected['task'] as String;
  final modelPath = modelBytes == null ? _models[name]!.$1 : null;
  final mode = expected['timestamp_ms'] == null
      ? VisionRunningMode.image
      : VisionRunningMode.video;
  switch (name) {
    case 'hand':
      final task = await HandLandmarker.create(
        HandLandmarkerOptions(
          modelPath: modelPath,
          modelBytes: modelBytes,
          runningMode: mode,
          numHands: options['num_hands'] as int,
        ),
      );
      return (
        (image, rotation, timestamp) async {
          final r = timestamp == null
              ? await task.detectImage(image, rotationDegrees: rotation)
              : await task.detectForVideo(
                  image,
                  rotationDegrees: rotation,
                  timestampMilliseconds: timestamp,
                );
          _size(
            r.imageWidth,
            r.imageHeight,
            r.timestampMilliseconds,
            image,
            timestamp,
          );
          return {
            'handedness': _categories(r.handedness),
            'hand_landmarks': _landmarks(r.handLandmarks),
            'hand_world_landmarks': _landmarks(r.handWorldLandmarks),
          };
        },
        task.dispose,
      );
    case 'gesture':
      final task = await GestureRecognizer.create(
        GestureRecognizerOptions(
          modelPath: modelPath,
          modelBytes: modelBytes,
          runningMode: mode,
          numHands: options['num_hands'] as int,
        ),
      );
      return (
        (image, rotation, timestamp) async {
          final r = timestamp == null
              ? await task.recognizeImage(image, rotationDegrees: rotation)
              : await task.recognizeForVideo(
                  image,
                  rotationDegrees: rotation,
                  timestampMilliseconds: timestamp,
                );
          _size(
            r.imageWidth,
            r.imageHeight,
            r.timestampMilliseconds,
            image,
            timestamp,
          );
          return {
            'gestures': _categories(r.gestures),
            'handedness': _categories(r.handedness),
            'hand_landmarks': _landmarks(r.handLandmarks),
            'hand_world_landmarks': _landmarks(r.handWorldLandmarks),
          };
        },
        task.dispose,
      );
    case 'pose':
      final task = await PoseLandmarker.create(
        PoseLandmarkerOptions(
          modelPath: modelPath,
          modelBytes: modelBytes,
          runningMode: mode,
          outputSegmentationMasks: options['output_segmentation_masks'] as bool,
        ),
      );
      return (
        (image, rotation, timestamp) async {
          final r = timestamp == null
              ? await task.detectImage(image, rotationDegrees: rotation)
              : await task.detectForVideo(
                  image,
                  rotationDegrees: rotation,
                  timestampMilliseconds: timestamp,
                );
          _size(
            r.imageWidth,
            r.imageHeight,
            r.timestampMilliseconds,
            image,
            timestamp,
          );
          if (r.segmentationMasks case final masks?) {
            expect(() => masks.clear(), throwsUnsupportedError);
          }
          return {
            'pose_landmarks': _landmarks(r.poseLandmarks),
            'pose_world_landmarks': _landmarks(r.poseWorldLandmarks),
            'segmentation_masks': r.segmentationMasks?.map(_mask).toList(),
          };
        },
        task.dispose,
      );
    case 'holistic':
      final task = await HolisticLandmarker.create(
        HolisticLandmarkerOptions(
          modelPath: modelPath,
          modelBytes: modelBytes,
          runningMode: mode,
          outputFaceBlendshapes: options['output_face_blendshapes'] as bool,
          outputPoseSegmentationMask:
              options['output_segmentation_mask'] as bool,
          minHandLandmarksConfidence:
              (options['min_hand_landmarks_confidence'] as num?)?.toDouble() ??
              0.5,
          minPoseDetectionConfidence:
              (options['min_pose_detection_confidence'] as num?)?.toDouble() ??
              0.5,
          minPoseSuppressionThreshold:
              (options['min_pose_suppression_threshold'] as num?)?.toDouble() ??
              0.5,
          minPosePresenceConfidence:
              (options['min_pose_landmarks_confidence'] as num?)?.toDouble() ??
              0.5,
        ),
      );
      return (
        (image, rotation, timestamp) async {
          final r = timestamp == null
              ? await task.detectImage(image, rotationDegrees: rotation)
              : await task.detectForVideo(
                  image,
                  rotationDegrees: rotation,
                  timestampMilliseconds: timestamp,
                );
          _size(
            r.imageWidth,
            r.imageHeight,
            r.timestampMilliseconds,
            image,
            timestamp,
          );
          return {
            'face_landmarks': _points(r.faceLandmarks),
            'pose_landmarks': _points(r.poseLandmarks),
            'pose_world_landmarks': _points(r.poseWorldLandmarks),
            'left_hand_landmarks': _points(r.leftHandLandmarks),
            'right_hand_landmarks': _points(r.rightHandLandmarks),
            'left_hand_world_landmarks': _points(r.leftHandWorldLandmarks),
            'right_hand_world_landmarks': _points(r.rightHandWorldLandmarks),
            'face_blendshapes': r.faceBlendshapes == null
                ? null
                : _categoryList(r.faceBlendshapes!),
            'segmentation_mask': r.poseSegmentationMask == null
                ? null
                : _mask(r.poseSegmentationMask!),
          };
        },
        task.dispose,
      );
    default:
      throw StateError('Unknown fixture task $name');
  }
}

void _size(
  int width,
  int height,
  int? actualTimestamp,
  VisionImage image,
  int? timestamp,
) {
  if (image.width != null) {
    expect(width, image.width);
    expect(height, image.height);
  }
  expect(actualTimestamp, timestamp);
}

List<List<Map<String, dynamic>>> _landmarks(List<List<VisionLandmark>> values) {
  expect(() => values.clear(), throwsUnsupportedError);
  return values.map(_points).toList();
}

List<Map<String, dynamic>> _points(List<VisionLandmark> values) {
  expect(() => values.clear(), throwsUnsupportedError);
  return [
    for (final v in values)
      {
        'x': v.x,
        'y': v.y,
        'z': v.z,
        'visibility': v.visibility,
        'presence': v.presence,
        'name': v.name,
      },
  ];
}

List<List<Map<String, dynamic>>> _categories(
  List<List<VisionCategory>> values,
) {
  expect(() => values.clear(), throwsUnsupportedError);
  return values.map(_categoryList).toList();
}

List<Map<String, dynamic>> _categoryList(List<VisionCategory> values) {
  expect(() => values.clear(), throwsUnsupportedError);
  return [
    for (final v in values)
      {
        'index': v.index,
        'score': v.score,
        'category_name': v.categoryName,
        'display_name': v.displayName,
      },
  ];
}

Map<String, dynamic> _mask(SegmentationMask mask) {
  final values = mask.confidence;
  expect(() => values[0] = 0, throwsUnsupportedError);
  var minimum = double.infinity;
  var maximum = double.negativeInfinity;
  var sum = 0.0;
  for (final value in values) {
    expect(value.isFinite, isTrue);
    if (value < minimum) minimum = value;
    if (value > maximum) maximum = value;
    sum += value;
  }
  return {
    'width': mask.width,
    'height': mask.height,
    'minimum': minimum,
    'maximum': maximum,
    'mean': sum / values.length,
    'samples': [
      for (var y = 0; y < mask.height; y += 17)
        for (var x = 0; x < mask.width; x += 19) values[y * mask.width + x],
    ],
  };
}

void _compare(
  dynamic actual,
  dynamic expected,
  String task, [
  String path = 'result',
]) {
  if (expected is Map) {
    expect(actual, isA<Map>(), reason: path);
    expect((actual as Map).keys, unorderedEquals(expected.keys), reason: path);
    for (final key in expected.keys) {
      _compare(actual[key], expected[key], task, '$path.$key');
    }
  } else if (expected is List) {
    expect(actual, isA<List>(), reason: path);
    expect(actual, hasLength(expected.length), reason: path);
    for (var i = 0; i < expected.length; i++) {
      _compare(actual[i], expected[i], task, '$path[$i]');
    }
  } else if (expected is double) {
    recordReferenceDelta(
      task,
      'cpu',
      path.contains('landmark') ? 'landmarks' : 'other',
      path,
      actual as num,
      expected,
    );
    expect(actual, closeTo(expected, 0.00001), reason: path);
  } else {
    expect(actual, expected, reason: path);
  }
}
