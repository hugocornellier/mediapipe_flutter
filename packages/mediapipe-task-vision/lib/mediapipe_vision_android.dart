/// Flutter's registration of Google's Android SDK behind the vision task
/// classes. Not for applications: import `mediapipe_vision.dart`.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:mediapipe_vision/mediapipe_vision.dart';
import 'package:mediapipe_vision/platform_interface.dart';

import 'src/capabilities/official_runtime_io.dart'
    show hasSourceBuiltAndroidFaceRuntime;

const _channel = MethodChannel('mediapipe_vision/android');

/// Masks travel apart from the method channel, whose reply is copied onto the
/// Java heap: a frame's confidence masks can outgrow it.
const _masks = BasicMessageChannel<ByteData>(
  'mediapipe_vision/android/masks',
  BinaryCodec(),
);

/// Replaces each mask the plugin named as [width, height, bytes per value,
/// id] with [width, height, values], fetched once over [_masks].
Future<void> _fetchMasks(Map<String, dynamic> result) async {
  Future<List<Object>> fetch(List named) async {
    final [width as int, height as int, depth as int, id as int] = named;
    final data = await _masks.send(ByteData(4)..setInt32(0, id, Endian.little));
    if (data == null || data.lengthInBytes != width * height * depth) {
      throw StateError('Mask $id did not arrive intact');
    }
    if (depth == 1) return [width, height, Uint8List.sublistView(data)];
    final aligned = data.offsetInBytes % 4 == 0
        ? data
        : ByteData.sublistView(Uint8List.fromList(Uint8List.sublistView(data)));
    return [width, height, Float32List.sublistView(aligned)];
  }

  for (final key in ['confidenceMasks', 'masks']) {
    if (result[key] case final List masks) {
      result[key] = [for (final mask in masks) await fetch(mask as List)];
    }
  }
  for (final key in ['categoryMask', 'mask']) {
    if (result[key] case final List mask) result[key] = await fetch(mask);
  }
}

/// Automatically registers the Android SDK backends with Flutter.
abstract final class MediaPipeVisionAndroid {
  /// Installs the backends before the first public task is created.
  static void registerWith() {
    // The GPU's name lets a task declare a GPU family it fails on, such as
    // Image Segmenter on PowerVR (UP-023), before anything runs there.
    taskPlatformGpuReader = () => _channel.invokeMethod<String>('gpuRenderer');
    faceLandmarkerBackendFactory = (o) => AndroidVisionTask.create({
      'task': 'face_landmarker',
      ..._base(o, o.runningMode),
      'numFaces': o.numFaces,
      'detectionConfidence': o.minFaceDetectionConfidence,
      'presenceConfidence': o.minFacePresenceConfidence,
      'trackingConfidence': o.minTrackingConfidence,
      'blendshapes': o.outputFaceBlendshapes,
      'matrices': o.outputFacialTransformationMatrixes,
    }, (r, t) => decodeFaceLandmarkerResult(_face(r, t)));
    handLandmarkerBackendFactory = (o) => AndroidVisionTask.create({
      'task': 'hand_landmarker',
      ..._base(o, o.runningMode),
      'numHands': o.numHands,
      'detectionConfidence': o.minHandDetectionConfidence,
      'presenceConfidence': o.minHandPresenceConfidence,
      'trackingConfidence': o.minTrackingConfidence,
    }, (r, t) => decodeHandLandmarkerResult(_hands(r, t)));
    poseLandmarkerBackendFactory = (o) => AndroidVisionTask.create({
      'task': 'pose_landmarker',
      ..._base(o, o.runningMode),
      'numPoses': o.numPoses,
      'detectionConfidence': o.minPoseDetectionConfidence,
      'presenceConfidence': o.minPosePresenceConfidence,
      'trackingConfidence': o.minTrackingConfidence,
      'masks': o.outputSegmentationMasks,
    }, (r, t) => decodePoseLandmarkerResult(_pose(r, t)));
    gestureRecognizerBackendFactory = (o) => AndroidVisionTask.create({
      'task': 'gesture_recognizer',
      ..._base(o, o.runningMode),
      'numHands': o.numHands,
      'detectionConfidence': o.minHandDetectionConfidence,
      'presenceConfidence': o.minHandPresenceConfidence,
      'trackingConfidence': o.minTrackingConfidence,
      'canned': _classifier(o.cannedGesturesClassifierOptions),
      'custom': _classifier(o.customGesturesClassifierOptions),
    }, (r, t) => decodeGestureRecognizerResult(_hands(r, t)));
    holisticLandmarkerBackendFactory = (o) => AndroidVisionTask.create({
      'task': 'holistic_landmarker',
      ..._base(o, o.runningMode),
      'faceDetectionConfidence': o.minFaceDetectionConfidence,
      'faceSuppressionThreshold': o.minFaceSuppressionThreshold,
      'facePresenceConfidence': o.minFacePresenceConfidence,
      'handLandmarksConfidence': o.minHandLandmarksConfidence,
      'poseDetectionConfidence': o.minPoseDetectionConfidence,
      'poseSuppressionThreshold': o.minPoseSuppressionThreshold,
      'posePresenceConfidence': o.minPosePresenceConfidence,
      'blendshapes': o.outputFaceBlendshapes,
      'masks': o.outputPoseSegmentationMask,
    }, (r, t) => decodeHolisticLandmarkerResult(_holistic(r, t)));
    faceDetectorBackendFactory = (o) => AndroidVisionTask.create({
      'task': 'face_detector',
      ..._base(o, o.runningMode),
      'detectionConfidence': o.minDetectionConfidence,
      'suppressionThreshold': o.minSuppressionThreshold,
    }, (r, t) => decodeFaceDetectorResult(_detections(r, t)));
    objectDetectorBackendFactory = (o) => AndroidVisionTask.create({
      'task': 'object_detector',
      ..._base(o, o.runningMode),
      'classifier': _limits(
        maxResults: o.maxResults,
        scoreThreshold: o.scoreThreshold,
        displayNamesLocale: o.displayNamesLocale,
        categoryAllowlist: o.categoryAllowlist,
        categoryDenylist: o.categoryDenylist,
      ),
    }, (r, t) => decodeObjectDetectorResult(_detections(r, t)));
    imageClassifierBackendFactory = (o) => AndroidVisionTask.create({
      'task': 'image_classifier',
      ..._base(o, o.runningMode),
      'classifier': _limits(
        maxResults: o.maxResults,
        scoreThreshold: o.scoreThreshold,
        displayNamesLocale: o.displayNamesLocale,
        categoryAllowlist: o.categoryAllowlist,
        categoryDenylist: o.categoryDenylist,
      ),
    }, (r, t) => decodeImageClassifierResult(_classifications(r, t)));
    imageEmbedderBackendFactory = (o) => AndroidVisionTask.create({
      'task': 'image_embedder',
      ..._base(o, o.runningMode),
      'l2Normalize': o.l2Normalize,
      'quantize': o.quantize,
    }, (r, t) => decodeImageEmbedderResult(_embeddings(r, t)));
    interactiveSegmenterBackendFactory = (o) async {
      try {
        final id = await _channel.invokeMethod<int>('create', {
          'task': 'interactive_segmenter',
          ..._base(o, RunningMode.image),
        });
        return AndroidInteractiveSegmenter._(id!);
      } on PlatformException catch (cause) {
        throw _error(cause);
      }
    };
    imageSegmenterBackendFactory = (o) => AndroidVisionTask.create({
      'task': 'image_segmenter',
      ..._base(o, o.runningMode),
      'confidenceMasks': o.outputConfidenceMasks,
      'categoryMask': o.outputCategoryMask,
      'displayNamesLocale': o.displayNamesLocale,
    }, (r, t) => decodeImageSegmenterResult(_data(r, t, r)));
    // `official_android_sdk: false` bundles the source-built face runtime;
    // the face tasks then call it through FFI rather than Google's SDK.
    if (hasSourceBuiltAndroidFaceRuntime()) {
      faceLandmarkerBackendFactory = null;
      faceDetectorBackendFactory = null;
    }
  }

  static Map<String, Object?> _limits({
    required int maxResults,
    required double scoreThreshold,
    required String? displayNamesLocale,
    required List<String> categoryAllowlist,
    required List<String> categoryDenylist,
  }) => {
    'maxResults': maxResults,
    'scoreThreshold': scoreThreshold,
    'displayNamesLocale': displayNamesLocale,
    'allowlist': categoryAllowlist,
    'denylist': categoryDenylist,
  };

  static Map<String, Object?> _classifier(ClassifierOptions o) => _limits(
    maxResults: o.maxResults,
    scoreThreshold: o.scoreThreshold,
    displayNamesLocale: o.displayNamesLocale,
    categoryAllowlist: o.categoryAllowlist,
    categoryDenylist: o.categoryDenylist,
  );

  // LIVE_STREAM runs on Google's VIDEO graph, with its flow limiter in the
  // task runner, so the plugin creates a VIDEO task for it.
  static Map<String, Object?> _base(TaskOptions o, RunningMode mode) => {
    'modelPath': o.modelPath,
    'modelBytes': o.modelBytes,
    'mode': mode == RunningMode.image ? 'image' : 'video',
    'delegate': o.delegate.name,
  };
}

// The Java plugin sends compact positional lists; these reshape them into
// Google's JavaScript result shape, which the shared decoder reads for the
// browser too. Landmarks and masks stay packed typed arrays.

VisionResultData _data(
  Map<String, dynamic> r,
  int? timestamp,
  Map<String, dynamic> result, {
  Float64List? landmarks,
  List<int>? counts,
  Float64List? worldLandmarks,
  List<int>? worldCounts,
  List<(String, List<int>)>? parts,
}) => VisionResultData(
  result: result,
  width: r['width'] as int,
  height: r['height'] as int,
  timestamp: timestamp,
  landmarks: landmarks,
  counts: counts,
  worldLandmarks: worldLandmarks,
  worldCounts: worldCounts,
  parts: parts,
);

VisionResultData _face(Map<String, dynamic> r, int? timestamp) => _data(
  r,
  timestamp,
  {
    'faceBlendshapes': [
      for (final face in r['blendshapes'] as List)
        {'categories': _categories(face as List)},
    ],
    'facialTransformationMatrixes': [
      for (final values in r['matrices'] as List)
        {'rows': 4, 'columns': 4, 'data': values as Float64List},
    ],
  },
  landmarks: r['landmarks'] as Float64List,
  counts: r['counts'] as Int32List,
);

/// Hand Landmarker and Gesture Recognizer, which add `gestures`.
VisionResultData _hands(Map<String, dynamic> r, int? timestamp) => _data(
  r,
  timestamp,
  {
    'handedness': [
      for (final hand in r['handedness'] as List) _categories(hand as List),
    ],
    if (r['gestures'] case final List gestures)
      'gestures': [for (final hand in gestures) _categories(hand as List)],
  },
  landmarks: r['landmarks'] as Float64List,
  counts: r['counts'] as Int32List,
  worldLandmarks: r['worldLandmarks'] as Float64List,
  worldCounts: r['worldCounts'] as Int32List,
);

VisionResultData _pose(Map<String, dynamic> r, int? timestamp) => _data(
  r,
  timestamp,
  {'segmentationMasks': ?r['masks']},
  landmarks: r['landmarks'] as Float64List,
  counts: r['counts'] as Int32List,
  worldLandmarks: r['worldLandmarks'] as Float64List,
  worldCounts: r['worldCounts'] as Int32List,
);

/// The seven landmark parts, concatenated into one buffer in `parts` order.
VisionResultData _holistic(Map<String, dynamic> r, int? timestamp) {
  const parts = [
    ('face', 'faceLandmarks'),
    ('pose', 'poseLandmarks'),
    ('poseWorld', 'poseWorldLandmarks'),
    ('leftHand', 'leftHandLandmarks'),
    ('leftHandWorld', 'leftHandWorldLandmarks'),
    ('rightHand', 'rightHandLandmarks'),
    ('rightHandWorld', 'rightHandWorldLandmarks'),
  ];
  final buffers = [for (final (key, _) in parts) r[key] as Float64List];
  final packed = Float64List(buffers.fold(0, (n, b) => n + b.length));
  var at = 0;
  for (final buffer in buffers) {
    packed.setAll(at, buffer);
    at += buffer.length;
  }
  final blendshapes = r['blendshapes'] as List?;
  return _data(
    r,
    timestamp,
    {
      if (blendshapes != null)
        'faceBlendshapes': [
          {'categories': _categories(blendshapes)},
        ],
      if (r['mask'] case final List mask) 'poseSegmentationMasks': [mask],
    },
    landmarks: packed,
    parts: [
      for (final (key, name) in parts) (name, r['${key}Counts'] as Int32List),
    ],
  );
}

/// Face and Object Detector boxes stay whole: Java's left, top, right and
/// bottom pixels go to the decoder as they are, without a float round trip.
VisionResultData _detections(Map<String, dynamic> r, int? timestamp) =>
    _data(r, timestamp, {
      'detections': [
        for (final d in r['detections'] as List)
          {
            'boundingBox': _box(d[0] as Float64List),
            'categories': _categories(d[1] as List),
            if ((d as List).length > 2)
              'keypoints': [
                for (final k in d[2] as List)
                  {'x': k[0], 'y': k[1], 'label': k[2], 'score': k[3]},
              ],
          },
      ],
    });

Map<String, double> _box(Float64List box) => {
  'left': box[0],
  'top': box[1],
  'right': box[2],
  'bottom': box[3],
};

VisionResultData _classifications(Map<String, dynamic> r, int? timestamp) =>
    _data(r, timestamp, {
      'classifications': [
        for (final head in r['classifications'] as List)
          {
            'categories': _categories(head[0] as List),
            'headIndex': head[1],
            'headName': head[2],
          },
      ],
    });

VisionResultData _embeddings(Map<String, dynamic> r, int? timestamp) =>
    _data(r, timestamp, {
      'embeddings': [
        for (final head in r['embeddings'] as List)
          {
            'floatEmbedding': head[0],
            'quantizedEmbedding': head[1],
            'headIndex': head[2],
            'headName': head[3],
          },
      ],
    });

/// Google's Java SDK reports an unlabeled category as an empty name, which
/// the decoder turns into null as the C, Python and iOS APIs report it.
List<Map<String, Object?>> _categories(List raw) => [
  for (final c in raw)
    {'index': c[0], 'score': c[1], 'categoryName': c[2], 'displayName': c[3]},
];

TaskException _error(PlatformException cause) =>
    TaskException(cause.message ?? cause.code, cause: cause);

/// The pixels or file of [image], as the plugin decodes it.
Map<String, Object?> _imageArguments(VisionImage image) => {
  'path': image.path,
  'pixels': image.pixels,
  'width': image.width,
  'height': image.height,
  'stride': image.bytesPerRow,
  'format': image.format?.name,
};

/// Google's stateful MagicTouch Interactive Segmenter on the plugin's worker.
final class AndroidInteractiveSegmenter implements InteractiveSegmenterBackend {
  AndroidInteractiveSegmenter._(this._id);
  final int _id;

  Future<T?> _call<T>(String method, Map<String, Object?> arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, {'id': _id, ...arguments});
    } on PlatformException catch (cause) {
      throw _error(cause);
    }
  }

  @override
  Future<void> setImage(VisionImage image) =>
      _call<void>('setImage', _imageArguments(image));

  @override
  Future<ConfidenceMask> segment(List<Stroke> strokes) async {
    final result = <String, dynamic>{
      'mask': await _call<List<Object?>>('segment', {
        'strokes': [
          for (final stroke in strokes)
            [
              stroke.brushMode.nativeValue,
              Float64List.fromList([
                for (final point in stroke.points) ...[point.x, point.y],
              ]),
              stroke.isCompleted,
            ],
        ],
      }),
    };
    await _fetchMasks(result);
    final [width, height, values] = result['mask'] as List;
    return confidenceMaskFromList([
      width,
      height,
      switch (values) {
        final Float32List floats => floats,
        final Uint8List bytes => Float32List.fromList([
          for (final v in bytes) v / 255,
        ]),
        _ => throw StateError('Unexpected mask values'),
      },
    ]);
  }

  @override
  Future<void> dispose() => _call<void>('close', const {});
}

/// One official Android SDK task on the plugin's worker thread.
final class AndroidVisionTask<R> implements VisionTaskBackend<R> {
  AndroidVisionTask._(this._id, this._decode);
  final int _id;
  final R Function(Map<String, dynamic> result, int? timestamp) _decode;

  /// Creates the task named by `arguments['task']` on the plugin's worker.
  static Future<AndroidVisionTask<R>> create<R>(
    Map<String, Object?> arguments,
    R Function(Map<String, dynamic> result, int? timestamp) decode,
  ) async {
    try {
      final id = await _channel.invokeMethod<int>('create', arguments);
      return AndroidVisionTask._(id!, decode);
    } on PlatformException catch (cause) {
      throw _error(cause);
    }
  }

  @override
  Future<R> detect(
    VisionImage image,
    int rotationDegrees,
    int? timestampMilliseconds, {
    VisionRegionOfInterest? regionOfInterest,
  }) async {
    try {
      final result = (await _channel.invokeMapMethod<String, dynamic>(
        'detect',
        {
          'id': _id,
          ..._imageArguments(image),
          'rotation': ((rotationDegrees % 360) + 360) % 360,
          'timestamp': timestampMilliseconds,
          'region': switch (regionOfInterest) {
            final r? => [r.left, r.top, r.right, r.bottom],
            null => null,
          },
        },
      ))!;
      await _fetchMasks(result);
      return _decode(result, timestampMilliseconds);
    } on PlatformException catch (cause) {
      throw _error(cause);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('close', {'id': _id});
    } on PlatformException catch (cause) {
      throw _error(cause);
    }
  }
}
