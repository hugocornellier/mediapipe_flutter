// Needs Flutter's test binding; `dart test` skips it (tag `flutter`).
@Tags(['flutter'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';
import 'package:mediapipe_vision/mediapipe_vision_android.dart';
import 'package:mediapipe_vision/platform_interface.dart';

/// The Android plugin's replies, shaped as its Java side sends them, run
/// through the Dart adapter and the shared decoder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('mediapipe_vision/android');
  late Map<String, Object?> reply;
  late Map<int, ByteData> masks;
  late List<MethodCall> calls;
  final image = VisionImage.fromPixels(
    pixels: Uint8List(12),
    width: 2,
    height: 2,
    format: VisionPixelFormat.rgb,
  );
  final model = Uint8List.fromList([1]);

  setUp(() {
    calls = [];
    masks = {};
    MediaPipeVisionAndroid.registerWith();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'create' => 7,
        'detect' || 'segment' => reply,
        _ => null,
      };
    });
    messenger.setMockMessageHandler('mediapipe_vision/android/masks', (
      message,
    ) async {
      return masks[message!.getInt32(0, Endian.little)];
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMessageHandler('mediapipe_vision/android/masks', null);
  });

  List<Object?> category(int index, double score, String name, String label) =>
      [index, score, name, label];

  ByteData floats(List<double> values) =>
      ByteData.sublistView(Float32List.fromList(values));

  test('hand landmarks, world landmarks and handedness', () async {
    reply = {
      'width': 640,
      'height': 480,
      'landmarks': Float64List.fromList([
        0.1, 0.2, 0.3, double.nan, double.nan, //
        0.4, 0.5, 0.6, 0.9, 0.8,
      ]),
      'counts': Int32List.fromList([2]),
      'worldLandmarks': Float64List.fromList([0.01, 0.02, 0.03, 0.5, 0.6]),
      'worldCounts': Int32List.fromList([1]),
      'handedness': [
        [category(1, 0.97, 'Right', '')],
      ],
    };
    final task = await HandLandmarker.create(
      HandLandmarkerOptions(modelBytes: model, delegate: Delegate.gpu),
    );
    final result = await task.detect(image, rotationDegrees: -90);
    expect(calls.first.arguments['delegate'], 'gpu');
    expect(calls.first.arguments['mode'], 'image');
    expect(calls[1].arguments['rotation'], 270);
    expect(result.imageWidth, 640);
    expect(result.timestampMilliseconds, isNull);
    expect(result.handLandmarks.single.map((p) => p.x), [0.1, 0.4]);
    expect(result.handLandmarks.single.first.visibility, isNull);
    expect(result.handWorldLandmarks.single.single, isA<Landmark>());
    expect(result.handWorldLandmarks.single.single.presence, 0.6);
    final side = result.handedness.single.single;
    expect(side.categoryName, 'Right');
    expect(side.displayName, isNull);
    await task.dispose();
    expect(calls.last.method, 'close');
  });

  test('gestures report index -1 in video mode', () async {
    reply = {
      'width': 1,
      'height': 1,
      'landmarks': Float64List(0),
      'counts': Int32List.fromList([0]),
      'worldLandmarks': Float64List(0),
      'worldCounts': Int32List.fromList([0]),
      'handedness': [
        [category(0, 0.9, 'Left', 'Left')],
      ],
      'gestures': [
        [category(3, 0.8, 'Thumb_Up', '')],
      ],
    };
    final task = await GestureRecognizer.create(
      GestureRecognizerOptions(
        modelBytes: model,
        runningMode: RunningMode.video,
        cannedGesturesClassifierOptions: ClassifierOptions(maxResults: 2),
      ),
    );
    final result = await task.recognizeForVideo(
      image,
      timestampMilliseconds: 5,
    );
    expect((calls.first.arguments['canned'] as Map)['maxResults'], 2);
    expect(calls[1].arguments['timestamp'], 5);
    expect(result.timestampMilliseconds, 5);
    expect(result.gestures.single.single.index, -1);
    expect(result.gestures.single.single.categoryName, 'Thumb_Up');
    expect(result.handLandmarks.single, isEmpty);
    await task.dispose();
  });

  test('a live stream task is a VIDEO task, and only the frames that run '
      'cross the channel', () async {
    final replies = <Completer<Map<String, Object?>>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method != 'detect') return call.method == 'create' ? 7 : null;
      final reply = Completer<Map<String, Object?>>();
      replies.add(reply);
      return reply.future;
    });
    Map<String, Object?> hands(int timestamp) => {
      'width': 2,
      'height': 2,
      'landmarks': Float64List(0),
      'counts': Int32List(0),
      'worldLandmarks': Float64List(0),
      'worldCounts': Int32List(0),
      'handedness': const [],
      'timestamp': timestamp,
    };
    final task = await HandLandmarker.create(
      HandLandmarkerOptions(
        modelBytes: model,
        runningMode: RunningMode.liveStream,
      ),
    );
    expect(calls.single.arguments['mode'], 'video');
    final results = <int?>[];
    task.results.listen((r) => results.add(r.timestampMilliseconds));
    for (var i = 0; i < 4; i++) {
      task.detectAsync(image, timestampMilliseconds: i, rotationDegrees: 90);
    }
    await pumpEventQueue();
    List<Object?> detected() => [
      for (final call in calls.where((c) => c.method == 'detect'))
        call.arguments['timestamp'],
    ];
    expect(detected(), [0]);
    expect(task.droppedFrames, 2);
    replies[0].complete(hands(0));
    await pumpEventQueue();
    expect(detected(), [0, 3]);
    expect(calls.last.arguments['rotation'], 90);
    final closing = task.dispose();
    await pumpEventQueue();
    expect(calls.last.method, 'detect', reason: 'the queued frame runs first');
    replies[1].complete(hands(3));
    await closing;
    expect(results, [0, 3]);
    expect(calls.last.method, 'close');
  });

  test('face landmarks, blendshapes and column-major matrices', () async {
    reply = {
      'width': 3,
      'height': 4,
      'landmarks': Float64List.fromList([0.5, 0.5, 0, double.nan, 1]),
      'counts': Int32List.fromList([1]),
      'blendshapes': [
        [category(9, 0.25, 'jawOpen', '')],
      ],
      'matrices': [Float64List.fromList(List.generate(16, (i) => i * 1.0))],
    };
    final task = await FaceLandmarker.create(
      FaceLandmarkerOptions(modelBytes: model),
    );
    final result = await task.detect(image);
    expect(result.faceLandmarks.single.single.presence, 1);
    expect(result.faceBlendshapes.single.single.categoryName, 'jawOpen');
    expect(result.facialTransformationMatrixes.single.at(0, 1), 4);
    await task.dispose();
  });

  test('pose masks arrive over the mask channel', () async {
    masks[4] = floats([0, 0.25, 0.5, 1]);
    reply = {
      'width': 2,
      'height': 2,
      'landmarks': Float64List(0),
      'counts': Int32List(0),
      'worldLandmarks': Float64List(0),
      'worldCounts': Int32List(0),
      'masks': [
        [2, 2, 4, 4],
      ],
    };
    final task = await PoseLandmarker.create(
      PoseLandmarkerOptions(modelBytes: model, outputSegmentationMasks: true),
    );
    final result = await task.detect(image);
    expect(result.poseLandmarks, isEmpty);
    expect(result.segmentationMasks!.single.confidence, [0, 0.25, 0.5, 1]);
    await task.dispose();
  });

  test('holistic parts are concatenated in order', () async {
    List<double> point(double x) => [x, 0, 0, double.nan, double.nan];
    masks[1] = floats([1, 0, 0, 1]);
    reply = {
      'width': 2,
      'height': 2,
      'face': Float64List.fromList(point(0.1)),
      'faceCounts': Int32List.fromList([1]),
      'pose': Float64List.fromList([...point(0.2), ...point(0.3)]),
      'poseCounts': Int32List.fromList([2]),
      'poseWorld': Float64List.fromList(point(0.4)),
      'poseWorldCounts': Int32List.fromList([1]),
      'leftHand': Float64List(0),
      'leftHandCounts': Int32List.fromList([0]),
      'leftHandWorld': Float64List(0),
      'leftHandWorldCounts': Int32List.fromList([0]),
      'rightHand': Float64List.fromList(point(0.5)),
      'rightHandCounts': Int32List.fromList([1]),
      'rightHandWorld': Float64List.fromList(point(0.6)),
      'rightHandWorldCounts': Int32List.fromList([1]),
      'blendshapes': [category(0, 0.1, '_neutral', '')],
      'mask': [2, 2, 4, 1],
    };
    final task = await HolisticLandmarker.create(
      HolisticLandmarkerOptions(modelBytes: model),
    );
    final result = await task.detect(image);
    expect(result.faceLandmarks.single.x, 0.1);
    expect(result.poseLandmarks.map((p) => p.x), [0.2, 0.3]);
    expect(result.poseWorldLandmarks.single.x, 0.4);
    expect(result.leftHandLandmarks, isEmpty);
    expect(result.leftHandWorldLandmarks, isEmpty);
    expect(result.rightHandLandmarks.single.x, 0.5);
    expect(result.rightHandWorldLandmarks.single.x, 0.6);
    expect(result.faceBlendshapes!.single.categoryName, '_neutral');
    expect(result.poseSegmentationMask!.confidence, [1, 0, 0, 1]);
    await task.dispose();
  });

  test('detection boxes keep whole pixels, keypoints and labels', () async {
    reply = {
      'width': 100,
      'height': 80,
      'detections': [
        [
          Float64List.fromList([20, 10.9, 59.99, 70]),
          [category(0, 0.9, '', '')],
          [
            [0.5, 0.25, null, null],
            [0.1, 0.2, 'eye', 0.7],
          ],
        ],
      ],
    };
    final faces = await FaceDetector.create(
      FaceDetectorOptions(modelBytes: model),
    );
    final face = (await faces.detect(image)).detections.single;
    expect(
      face.boundingBox,
      const BoundingBox(left: 20, top: 10, right: 59, bottom: 70),
    );
    expect(face.categories.single.categoryName, isNull);
    expect(face.keypoints.first.label, isNull);
    expect(face.keypoints.last.label, 'eye');
    expect(face.keypoints.last.score, 0.7);
    await faces.dispose();

    reply = {
      'width': 100,
      'height': 80,
      'detections': [
        [
          Float64List.fromList([1, 2, 3, 4]),
          [category(17, 0.6, 'dog', 'Dog')],
          <Object?>[],
        ],
      ],
    };
    final objects = await ObjectDetector.create(
      ObjectDetectorOptions(modelBytes: model, maxResults: 3),
    );
    final object = (await objects.detect(image)).detections.single;
    expect((calls.last.arguments as Map)['id'], 7);
    expect(object.boundingBox.right, 3);
    expect(object.categories.single.displayName, 'Dog');
    expect(object.keypoints, isEmpty);
    await objects.dispose();
  });

  test('classification heads and embeddings', () async {
    reply = {
      'width': 2,
      'height': 2,
      'classifications': [
        [
          [category(5, 0.5, 'cat', '')],
          0,
          'probability',
        ],
      ],
    };
    final classifier = await ImageClassifier.create(
      ImageClassifierOptions(modelBytes: model),
    );
    final head = (await classifier.classify(
      image,
      regionOfInterest: VisionRegionOfInterest(
        left: 0,
        top: 0,
        right: 0.5,
        bottom: 1,
      ),
    )).classifications.single;
    expect(calls.last.arguments['region'], [0, 0, 0.5, 1]);
    expect(head.headName, 'probability');
    expect(head.categories.single.index, 5);
    await classifier.dispose();

    reply = {
      'width': 2,
      'height': 2,
      'embeddings': [
        [
          Float64List.fromList([0.5, -0.25]),
          null,
          0,
          '',
        ],
        [
          null,
          Uint8List.fromList([1, 255]),
          1,
          'quantized',
        ],
      ],
    };
    final embedder = await ImageEmbedder.create(
      ImageEmbedderOptions(modelBytes: model),
    );
    final [floating, quantized] = (await embedder.embed(image)).embeddings;
    expect(floating.floatEmbedding, isA<Float32List>());
    expect(floating.floatEmbedding, [0.5, -0.25]);
    expect(floating.headName, isNull);
    expect(quantized.quantizedEmbedding, [1, 255]);
    expect(quantized.headName, 'quantized');
    await embedder.dispose();
  });

  test('segmenter masks, quality scores and labels', () async {
    masks
      ..[1] = floats([0.1, 0.2, 0.3, 0.4])
      ..[2] = ByteData.sublistView(Uint8List.fromList([0, 1, 1, 0]));
    reply = {
      'width': 2,
      'height': 2,
      'confidenceMasks': [
        [2, 2, 4, 1],
      ],
      'categoryMask': [2, 2, 1, 2],
      'qualityScores': Float32List.fromList([0.75]),
      'labels': ['background'],
    };
    final task = await ImageSegmenter.create(
      ImageSegmenterOptions(modelBytes: model, outputCategoryMask: true),
    );
    final result = await task.segment(image);
    expect(result.confidenceMasks!.single.confidence[3], closeTo(0.4, 1e-6));
    expect(result.categoryMask!.categories, [0, 1, 1, 0]);
    expect(result.qualityScores, [0.75]);
    expect(result.labels, ['background']);
    await task.dispose();
  });

  test('interactive segmenter reads a byte mask as confidences', () async {
    masks[3] = ByteData.sublistView(Uint8List.fromList([0, 255, 51, 0]));
    reply = {};
    final task = await InteractiveSegmenter.create(
      InteractiveSegmenterOptions(modelBytes: model),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'segment' ? <Object?>[2, 2, 1, 3] : null;
    });
    await task.setImage(image);
    final mask = await task.segment([
      Stroke(
        brushMode: BrushMode.positive,
        points: const [NormalizedKeypoint(x: 0.5, y: 0.5)],
      ),
    ]);
    final strokes = calls.last.arguments['strokes'] as List;
    expect((strokes.single as List).first, BrushMode.positive.nativeValue);
    expect(mask.confidence, [0, 1, closeTo(0.2, 1e-6), 0]);
    await task.dispose();
  });

  test('plugin errors become TaskException', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'task', message: 'No GPU here.');
    });
    await expectLater(
      FaceDetector.create(FaceDetectorOptions(modelBytes: model)),
      throwsA(
        isA<TaskException>().having(
          (e) => e.message,
          'message',
          'No GPU here.',
        ),
      ),
    );
  });

  test('registration installs a backend for every task', () {
    expect(faceDetectorBackendFactory, isNotNull);
    expect(faceLandmarkerBackendFactory, isNotNull);
    expect(interactiveSegmenterBackendFactory, isNotNull);
    expect(taskPlatformGpuReader, isNotNull);
  });
}
