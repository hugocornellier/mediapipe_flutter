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

/// Comma-separated subset of `face_detector,object_detector,image_classifier`.
const _only = String.fromEnvironment('SDK_TASKS');

/// Box edges may move by this share of the image's longer side between
/// Google's runtime builds and image decoders.
const _boxShare = 0.02;

/// Scores may move by this much between runtime builds and delegates.
const _scoreDelta = 0.05;

// Face Detector, Object Detector and Image Classifier through Google's
// official mobile SDKs: iOS through the package's Objective-C adapter, Android
// through mediapipe_flutter_vision_android.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final subject in _subjects) {
    if (_only.isNotEmpty && !_only.split(',').contains(subject.name)) continue;

    testWidgets(
      'official SDK ${subject.name}: references, pixels, rotation, CPU and GPU',
      (tester) async {
        await tester.runAsync(() async {
          expect(Platform.isAndroid || Platform.isIOS, isTrue);
          if (Platform.isAndroid) {
            expect(
              subject.registered(),
              isTrue,
              reason: 'the Android SDK plugin must register automatically',
            );
          }
          final assets = await GalleryAssets.unpack();
          final model = await _model(subject.model);
          final frame = await loadSample('portrait.jpg');
          final references = <VisionDelegate, List<_Item>>{};
          for (final delegate in [
            VisionDelegate.cpu,
            if (_gpu != 'skip') VisionDelegate.gpu,
          ]) {
            final _Task task;
            try {
              task = await subject.open(
                model,
                delegate,
                VisionRunningMode.image,
              );
            } on Exception catch (error) {
              if (delegate == VisionDelegate.cpu || _gpu == 'required') {
                rethrow;
              }
              _report(subject, 'gpu_unavailable', {'error': '$error'});
              continue;
            }
            try {
              final official = <String, double>{};
              for (final sample in subject.samples) {
                final result = await task.image(
                  VisionImage.fromFile(assets.path(sample)),
                );
                _report(subject, 'found', {
                  'delegate': delegate.name,
                  'sample': sample,
                  'items': [
                    for (final item in result.items)
                      '${item.name} ${item.score.toStringAsFixed(3)}',
                  ],
                });
                official[sample] = subject.compare(sample, result, delegate);
              }
              final reference = await task.image(frame.image);
              references[delegate] = reference.items;
              for (final format in VisionPixelFormat.values) {
                final padded = await task.image(paddedImage(frame, format));
                expect(
                  _itemDelta(reference, padded, exact: true),
                  lessThan(1e-4),
                  reason: format.name,
                );
              }
              for (final turn in [90, 180, 270]) {
                final rotated = rotatedImage(frame, (360 - turn) % 360);
                final result = await task.image(rotated, rotation: turn);
                // The model scores a turned image a little differently, so
                // only the leading result and the reported size must hold.
                expect(result.items, isNotEmpty);
                expect(result.items.first.name, reference.items.first.name);
                expect(
                  result.width,
                  turn % 180 == 0 ? frame.width : frame.height,
                );
              }
              final blank = await task.image(blankImage());
              if (subject.name != 'image_classifier') {
                expect(blank.items, isEmpty);
              }
              if (subject.name == 'image_classifier') {
                // A full-frame region of interest is the whole image; this
                // also pins the region's normalized coordinates.
                final whole = await task.image(
                  frame.image,
                  region: VisionRegionOfInterest(
                    left: 0,
                    top: 0,
                    right: 1,
                    bottom: 1,
                  ),
                );
                expect(_itemDelta(reference, whole), lessThan(1e-3));
              }
              _report(subject, 'image', {
                'delegate': delegate.name,
                'official_max_delta': official,
                'top': reference.items.firstOrNull?.name,
              });
            } finally {
              await task.dispose();
            }
            await task.dispose();
            await expectLater(task.image(frame.image), throwsStateError);
          }
          if (references.length == 2) {
            // Recorded, not asserted: each delegate already matched Google's
            // own output for it, and those two legitimately differ.
            String top(List<_Item> items) => [
              for (final item in items.take(3))
                '${item.name} ${item.score.toStringAsFixed(3)}',
            ].join(', ');
            _report(subject, 'cpu_gpu', {
              'cpu': top(references[VisionDelegate.cpu]!),
              'gpu': top(references[VisionDelegate.gpu]!),
            });
          }
          await expectLater(
            subject.open(
              Uint8List.fromList([1, 2, 3]),
              VisionDelegate.cpu,
              VisionRunningMode.image,
            ),
            throwsA(isA<Exception>()),
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    testWidgets(
      'official SDK ${subject.name} VIDEO: queued frames and timestamps',
      (tester) async {
        await tester.runAsync(() async {
          final frame = await loadSample('portrait.jpg');
          final task = await subject.open(
            await _model(subject.model),
            VisionDelegate.cpu,
            VisionRunningMode.video,
          );
          try {
            await expectLater(task.image(frame.image), throwsStateError);
            await expectLater(task.video(frame.image, -1), throwsArgumentError);
            final queued = await Future.wait([
              task.video(frame.image, 0),
              task.video(frame.image, 33),
            ]);
            expect(queued.map((r) => r.timestamp), [0, 33]);
            await expectLater(task.video(frame.image, 33), throwsArgumentError);
            for (var i = 2; i < 12; i++) {
              final result = await task.video(frame.image, i * 33);
              expect(result.items, isNotEmpty);
              expect(result.timestamp, i * 33);
            }
            _report(subject, 'video', {'frames': 12});
          } finally {
            await task.dispose();
          }
        });
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

/// A detection's box and top category, or a class with a zero box.
typedef _Item = ({
  double left,
  double top,
  double right,
  double bottom,
  double score,
  String? name,
});

typedef _Result = ({List<_Item> items, int width, int height, int? timestamp});

/// One open task behind a uniform face, whatever its own method names.
final class _Task {
  _Task(this.image, this.video, this.dispose);
  final Future<_Result> Function(
    VisionImage image, {
    int rotation,
    VisionRegionOfInterest? region,
  })
  image;
  final Future<_Result> Function(VisionImage image, int timestamp) video;
  final Future<void> Function() dispose;
}

final class _Subject {
  const _Subject({
    required this.name,
    required this.model,
    required this.samples,
    required this.registered,
    required this.open,
    this.cutoff = 0,
    this.maxResults,
  });

  /// As in the references and SDK_TASKS.
  final String name;
  final String model;

  /// Gallery samples with an official reference.
  final List<String> samples;
  final bool Function() registered;

  /// The score below which the task drops detections.
  final double cutoff;

  /// The most detections the task returns, when limited.
  final int? maxResults;
  final Future<_Task> Function(
    Uint8List model,
    VisionDelegate delegate,
    VisionRunningMode mode,
  )
  open;

  /// Checks [result] against Google's reference for [sample] from the same
  /// [delegate]; returns the largest box difference as a share of the image's
  /// longer side. Google's GPU inference scores these models differently from
  /// its CPU inference (portrait.jpg's top class: 0.31 on CPU, 0.80 on GPU, in
  /// its wheel, its browser runtime and its Android SDK alike), so GPU results
  /// are held to the wheel's GPU output, never to the CPU one.
  double compare(String sample, _Result result, VisionDelegate delegate) {
    final gpu = delegate == VisionDelegate.gpu;
    if (name == 'image_classifier') {
      final expected = gpu
          ? officialGpuClassifierReference
          : officialClassifierReference;
      expect(
        result.items.take(expected.length).map((c) => c.name),
        expected.map((c) => c.$1),
      );
      var maximum = 0.0;
      for (final (i, (_, score)) in expected.indexed) {
        maximum = math.max(maximum, (result.items[i].score - score).abs());
      }
      expect(maximum, lessThan(_scoreDelta));
      return maximum;
    }
    // A detection scored within the tolerance of the cutoff, or of the
    // lowest score kept when maxResults filled the list, may fall on either
    // side of it in another runtime build (a 0.301 bottle on iOS, absent in
    // Google's 1.0.0 wheel; a 0.536 potted plant against a 0.535 person for
    // the fifth place). Only clear detections must match.
    final reference = (gpu
        ? officialGpuDetectionReferences
        : officialDetectionReferences)[name]![sample]!;
    final floor = maxResults != null && reference.length >= maxResults!
        ? reference.map((box) => box.score).reduce(math.min)
        : cutoff;
    final clear = floor + _scoreDelta;
    final expected = [
      for (final box in reference)
        if (box.score >= clear) box,
    ];
    final items = [
      for (final item in result.items)
        if (item.score >= clear) item,
    ];
    expect(items, hasLength(expected.length), reason: sample);
    final side = math.max(result.width, result.height);
    var maximum = 0.0;
    // Close scores may swap order between builds, so each reference box is
    // paired with the nearest unclaimed detection of the same label.
    final unclaimed = [...items];
    for (final box in expected) {
      double distance(_Item got) => [
        (got.left - box.left).abs(),
        (got.top - box.top).abs(),
        (got.right - box.right).abs(),
        (got.bottom - box.bottom).abs(),
      ].reduce(math.max);
      final candidates = unclaimed.where((got) => got.name == box.name);
      expect(candidates, isNotEmpty, reason: '$sample ${box.name}');
      final got = candidates.reduce(
        (a, b) => distance(a) <= distance(b) ? a : b,
      );
      unclaimed.remove(got);
      expect((got.score - box.score).abs(), lessThan(_scoreDelta));
      maximum = math.max(maximum, distance(got) / side);
    }
    expect(maximum, lessThan(_boxShare), reason: sample);
    return maximum;
  }
}

_Result _detections<T>(
  List<T> detections,
  _Item Function(T) item,
  int width,
  int height,
  int? timestamp,
) => (
  items: [for (final d in detections) item(d)],
  width: width,
  height: height,
  timestamp: timestamp,
);

final _subjects = <_Subject>[
  _Subject(
    name: 'face_detector',
    model: 'blaze_face_short_range.tflite',
    samples: const ['portrait.jpg', 'group.jpeg'],
    registered: () => faceDetectorBackendFactory != null,
    // FaceDetectorOptions' default minDetectionConfidence.
    cutoff: 0.5,
    open: (model, delegate, mode) async {
      final task = await FaceDetector.create(
        FaceDetectorOptions(
          modelBytes: model,
          delegate: delegate,
          runningMode: mode,
        ),
      );
      _Result map(FaceDetectorResult r) => _detections(
        r.detections,
        (d) {
          expect(d.keypoints, hasLength(6));
          final box = d.boundingBox;
          return (
            left: box.left.toDouble(),
            top: box.top.toDouble(),
            right: box.right.toDouble(),
            bottom: box.bottom.toDouble(),
            score: d.categories.first.score,
            name: d.categories.first.categoryName,
          );
        },
        r.imageWidth,
        r.imageHeight,
        r.timestampMilliseconds,
      );
      return _Task(
        (image, {rotation = 0, region}) async =>
            map(await task.detectImage(image, rotationDegrees: rotation)),
        (image, timestamp) async => map(
          await task.detectForVideo(image, timestampMilliseconds: timestamp),
        ),
        task.dispose,
      );
    },
  ),
  _Subject(
    name: 'object_detector',
    model: 'efficientdet_lite0.tflite',
    samples: const ['portrait.jpg', 'group.jpeg'],
    registered: () => objectDetectorBackendFactory != null,
    cutoff: 0.3,
    maxResults: 5,
    open: (model, delegate, mode) async {
      // The reference's limits.
      final task = await ObjectDetector.create(
        ObjectDetectorOptions(
          modelBytes: model,
          delegate: delegate,
          runningMode: mode,
          maxResults: 5,
          scoreThreshold: 0.3,
        ),
      );
      _Result map(ObjectDetectorResult r) => _detections(
        r.detections,
        (d) {
          final box = d.boundingBox;
          return (
            left: box.left.toDouble(),
            top: box.top.toDouble(),
            right: box.right.toDouble(),
            bottom: box.bottom.toDouble(),
            score: d.categories.first.score,
            name: d.categories.first.categoryName,
          );
        },
        r.imageWidth,
        r.imageHeight,
        r.timestampMilliseconds,
      );
      return _Task(
        (image, {rotation = 0, region}) async =>
            map(await task.detectImage(image, rotationDegrees: rotation)),
        (image, timestamp) async => map(
          await task.detectForVideo(image, timestampMilliseconds: timestamp),
        ),
        task.dispose,
      );
    },
  ),
  _Subject(
    name: 'image_classifier',
    model: 'efficientnet_lite0.tflite',
    samples: const ['portrait.jpg'],
    registered: () => imageClassifierBackendFactory != null,
    open: (model, delegate, mode) async {
      final task = await ImageClassifier.create(
        ImageClassifierOptions(
          modelBytes: model,
          delegate: delegate,
          runningMode: mode,
          maxResults: 3,
        ),
      );
      _Result map(ImageClassifierResult r) => (
        items: [
          for (final c in r.classifications.single.categories)
            (
              left: 0.0,
              top: 0.0,
              right: 0.0,
              bottom: 0.0,
              score: c.score,
              name: c.categoryName,
            ),
        ],
        width: r.imageWidth,
        height: r.imageHeight,
        timestamp: r.timestampMilliseconds,
      );
      return _Task(
        (image, {rotation = 0, region}) async => map(
          await task.classifyImage(
            image,
            rotationDegrees: rotation,
            regionOfInterest: region,
          ),
        ),
        (image, timestamp) async => map(
          await task.classifyForVideo(image, timestampMilliseconds: timestamp),
        ),
        task.dispose,
      );
    },
  ),
];

Future<Uint8List> _model(String name) async {
  final bytes = await rootBundle.load('assets/models/$name');
  return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}

/// Largest score difference, and box difference as a share of the longer
/// side; names must match. [exact] also requires the same count.
double _itemDelta(_Result a, _Result b, {bool exact = false}) {
  if (exact) expect(b.items, hasLength(a.items.length));
  final side = math.max(a.width, a.height);
  var maximum = 0.0;
  for (final (i, p) in a.items.take(b.items.length).indexed) {
    final q = b.items[i];
    expect(q.name, p.name);
    maximum = math.max(maximum, (p.score - q.score).abs());
    for (final (x, y) in [
      (p.left, q.left),
      (p.top, q.top),
      (p.right, q.right),
      (p.bottom, q.bottom),
    ]) {
      maximum = math.max(maximum, (x - y).abs() / side);
    }
  }
  return maximum;
}

void _report(_Subject subject, String event, Map<String, Object?> data) {
  // Kept in the device log (logcat, the simulator console) for the record.
  // ignore: avoid_print
  print(
    'SDK_DETECTION_TASK ${jsonEncode({'task': subject.name, 'event': event, ...data})}',
  );
}
