import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';
import 'package:mediapipe_flutter_vision/models.dart';
import 'package:test/test.dart';
import 'support/face_reference.dart';

const _fixtures = 'test/fixtures/face_detection';
const _models = {
  'image': ('models/deeplab_v3.tflite', deepLabV3Sha256),
  'interactive': ('models/magic_touch.tflite', magicTouchSha256),
};
// DeepLab-v3's Pascal VOC order; the legacy task has no label API at all.
const _deepLabLabels = 21;
typedef _Task = (
  Future<Map<String, dynamic>> Function(VisionImage, int, int?),
  Future<void> Function(),
);

// Both tasks are validated against the official wheel that ships the same
// native library on Linux and Windows. macOS loads our source build, whose CPU
// results are not validated; see upstream-issues.md UP-004.
final _unvalidatedHost = Platform.isMacOS
    ? 'macOS source-build CPU output is unvalidated; see UP-004'
    : null;

void main() {
  final reference = loadFaceReference(
    'segmenter_tasks',
    'official_reference.json',
  );
  final cases = (reference['cases'] as List).cast<Map<String, dynamic>>();
  setUpAll(() {
    for (final (name, row) in _models.entries.map((e) => (e.key, e.value))) {
      expect(sha256.convert(File(row.$1).readAsBytesSync()).toString(), row.$2);
      expect(reference['models'][name], row.$2);
    }
  });
  for (final expected in cases.where((c) => c['timestamp_ms'] == null)) {
    test(
      'official ${expected['task']} / ${expected['input']} / ${expected['options']}',
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
          );
        } finally {
          await close();
        }
      },
      skip: _unvalidatedHost,
    );
  }
  test(
    'image segmenter video matches the official frames through queued disposal',
    () async {
      final frames = cases
          .where((c) => c['task'] == 'image' && c['timestamp_ms'] != null)
          .where((c) => (c['options'] as Map)['output_category_mask'] == true)
          .toList();
      expect(frames, hasLength(3));
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
        _compare(results[i], frames[i]['result']);
      }
    },
    skip: _unvalidatedHost,
  );
  for (final name in _models.keys) {
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
  test('the model label list orders both mask kinds', () async {
    final expected = cases.firstWhere(
      (c) =>
          c['task'] == 'image' &&
          c['input'] == 'rgb' &&
          c['timestamp_ms'] == null,
    );
    final task = await ImageSegmenter.create(
      ImageSegmenterOptions(modelPath: _models['image']!.$1),
    );
    try {
      // The official Python bindings do not expose this list, so it is
      // checked against the model's documented categories, not an official
      // output. The legacy task has no label API and reports none.
      final result = await task.segmentImage(_image(expected));
      expect(result.labels, hasLength(_deepLabLabels));
      expect(result.labels.first, 'background');
      expect(result.labels, contains('person'));
      expect(result.confidenceMasks, hasLength(_deepLabLabels));
      expect(() => result.labels.clear(), throwsUnsupportedError);
    } finally {
      await task.dispose();
    }
    final legacy = await InteractiveSegmenterLegacy.create(
      InteractiveSegmenterLegacyOptions(modelPath: _models['interactive']!.$1),
    );
    try {
      final result = await legacy.segmentImage(
        _image(expected),
        keypoint: SegmentationPoint(x: 0.5, y: 0.4),
      );
      expect(result.labels, isEmpty);
    } finally {
      await legacy.dispose();
    }
  }, skip: _unvalidatedHost);
  test('options reject empty mask selections and malformed metadata', () {
    expect(
      () => ImageSegmenterOptions(
        modelPath: 'model',
        outputConfidenceMasks: false,
      ),
      throwsArgumentError,
    );
    expect(
      () => InteractiveSegmenterLegacyOptions(
        modelPath: 'model',
        outputConfidenceMasks: false,
      ),
      throwsArgumentError,
    );
    expect(
      () => ImageSegmenterOptions(modelPath: 'model', displayNamesLocale: ''),
      throwsArgumentError,
    );
    expect(
      () => ImageSegmenterOptions(modelPath: 'model', modelBytes: Uint8List(4)),
      throwsArgumentError,
    );
    expect(() => SegmentationPoint(x: 1.5, y: 0.5), throwsArgumentError);
    expect(
      () => CategoryMask(width: 2, height: 2, categories: Uint8List(3)),
      throwsArgumentError,
    );
  });
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
  const width = 301;
  const height = 209;
  var pixels = File('$_fixtures/portrait-301x209.rgb').readAsBytesSync();
  if (expected['input'] != 'blank') {
    expect(sha256.convert(pixels).toString(), expected['sha256']);
  }
  var format = VisionPixelFormat.rgb;
  switch (expected['input']) {
    case 'blank':
      pixels = Uint8List(width * height * 3);
    case 'rgba':
      final rgba = Uint8List(width * height * 4);
      for (var i = 0; i < width * height; i++) {
        rgba.setRange(i * 4, i * 4 + 3, pixels, i * 3);
        rgba[i * 4 + 3] = 255;
      }
      pixels = rgba;
      format = VisionPixelFormat.rgba;
    case 'rotated':
      final rotated = Uint8List(pixels.length);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final output = ((width - 1 - x) * height + y) * 3;
          rotated.setRange(output, output + 3, pixels, (y * width + x) * 3);
        }
      }
      return VisionImage.fromPixels(
        pixels: rotated,
        width: height,
        height: width,
        format: format,
      );
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
  final confidence = options['output_confidence_masks'] as bool;
  final category = options['output_category_mask'] as bool;
  if (name == 'image') {
    final task = await ImageSegmenter.create(
      ImageSegmenterOptions(
        modelPath: modelPath,
        modelBytes: modelBytes,
        runningMode: expected['timestamp_ms'] == null
            ? VisionRunningMode.image
            : VisionRunningMode.video,
        outputConfidenceMasks: confidence,
        outputCategoryMask: category,
      ),
    );
    return (
      (image, rotation, timestamp) async => _summary(
        timestamp == null
            ? await task.segmentImage(image, rotationDegrees: rotation)
            : await task.segmentForVideo(
                image,
                rotationDegrees: rotation,
                timestampMilliseconds: timestamp,
              ),
        image,
        timestamp,
      ),
      task.dispose,
    );
  }
  final task = await InteractiveSegmenterLegacy.create(
    InteractiveSegmenterLegacyOptions(
      modelPath: modelPath,
      modelBytes: modelBytes,
      outputConfidenceMasks: confidence,
      outputCategoryMask: category,
    ),
  );
  final point = expected['keypoint'] as Map<String, dynamic>;
  return (
    (image, rotation, timestamp) async => _summary(
      await task.segmentImage(
        image,
        rotationDegrees: rotation,
        keypoint: SegmentationPoint(
          x: (point['x'] as num).toDouble(),
          y: (point['y'] as num).toDouble(),
        ),
      ),
      image,
      timestamp,
    ),
    task.dispose,
  );
}

Map<String, dynamic> _summary(
  SegmentationResult result,
  VisionImage image,
  int? timestamp,
) {
  if (image.width != null) {
    expect(result.imageWidth, image.width);
    expect(result.imageHeight, image.height);
  }
  expect(result.timestampMilliseconds, timestamp);
  if (result.confidenceMasks case final masks?) {
    expect(() => masks.clear(), throwsUnsupportedError);
  }
  if (result.qualityScores case final scores?) {
    expect(scores.every((value) => value >= 0 && value <= 1), isTrue);
    expect(() => scores[0] = 2, throwsUnsupportedError);
  }
  return {
    'confidence_masks': result.confidenceMasks
        ?.map((mask) => _mask(mask.width, mask.height, mask.confidence))
        .toList(),
    'category_mask': result.categoryMask == null
        ? null
        : _mask(
            result.categoryMask!.width,
            result.categoryMask!.height,
            result.categoryMask!.categories,
          ),
  };
}

/// The same native library fills both sides on one host, so the mask bytes
/// match exactly; the statistics only make a mismatch readable.
Map<String, dynamic> _mask(int width, int height, List<num> values) {
  expect(values, hasLength(width * height));
  var minimum = double.infinity;
  var maximum = double.negativeInfinity;
  var sum = 0.0;
  for (final value in values) {
    final number = value.toDouble();
    expect(number.isFinite, isTrue);
    if (number < minimum) minimum = number;
    if (number > maximum) maximum = number;
    sum += number;
  }
  final bytes = values is Float32List
      ? Float32List.fromList(values).buffer.asUint8List()
      : Uint8List.fromList(values.cast<int>());
  return {
    'width': width,
    'height': height,
    'sha256': sha256.convert(bytes).toString(),
    'minimum': minimum,
    'maximum': maximum,
    'mean': sum / values.length,
  };
}

void _compare(dynamic actual, dynamic expected, [String path = 'result']) {
  if (expected is Map) {
    expect(actual, isA<Map>(), reason: path);
    expect((actual as Map).keys, unorderedEquals(expected.keys), reason: path);
    for (final key in expected.keys) {
      _compare(actual[key], expected[key], '$path.$key');
    }
  } else if (expected is List) {
    expect(actual, isA<List>(), reason: path);
    expect(actual, hasLength(expected.length), reason: path);
    for (var i = 0; i < expected.length; i++) {
      _compare(actual[i], expected[i], '$path[$i]');
    }
  } else if (expected is double) {
    expect(actual, closeTo(expected, 0.00001), reason: path);
  } else {
    expect(actual, expected, reason: path);
  }
}
