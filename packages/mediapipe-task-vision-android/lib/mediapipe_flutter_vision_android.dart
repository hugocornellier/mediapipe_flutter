import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/face_landmarker_backend.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

const _channel = MethodChannel('mediapipe_flutter_vision/android');

/// Masks travel apart from the method channel, whose reply is copied onto the
/// Java heap: a frame's confidence masks can outgrow it.
const _masks = BasicMessageChannel<ByteData>(
  'mediapipe_flutter_vision/android/masks',
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
    faceLandmarkerBackendFactory = (o) => AndroidVisionTask.create(
      {
        'task': 'face_landmarker',
        ..._base(o.modelPath, o.modelBytes, o.runningMode, o.delegate),
        'numFaces': o.numFaces,
        'detectionConfidence': o.minFaceDetectionConfidence,
        'presenceConfidence': o.minFacePresenceConfidence,
        'trackingConfidence': o.minTrackingConfidence,
        'blendshapes': o.outputFaceBlendshapes,
        'matrices': o.outputFacialTransformationMatrixes,
      },
      _face,
      FaceLandmarkerException.new,
    );
    handLandmarkerBackendFactory = (o) => AndroidVisionTask.create(
      {
        'task': 'hand_landmarker',
        ..._base(o.modelPath, o.modelBytes, o.runningMode, o.delegate),
        'numHands': o.numHands,
        'detectionConfidence': o.minHandDetectionConfidence,
        'presenceConfidence': o.minHandPresenceConfidence,
        'trackingConfidence': o.minTrackingConfidence,
      },
      _hand,
      VisionTaskException.new,
    );
    poseLandmarkerBackendFactory = (o) => AndroidVisionTask.create(
      {
        'task': 'pose_landmarker',
        ..._base(o.modelPath, o.modelBytes, o.runningMode, o.delegate),
        'numPoses': o.numPoses,
        'detectionConfidence': o.minPoseDetectionConfidence,
        'presenceConfidence': o.minPosePresenceConfidence,
        'trackingConfidence': o.minTrackingConfidence,
        'masks': o.outputSegmentationMasks,
      },
      _pose,
      VisionTaskException.new,
    );
    gestureRecognizerBackendFactory = (o) => AndroidVisionTask.create(
      {
        'task': 'gesture_recognizer',
        ..._base(o.modelPath, o.modelBytes, o.runningMode, o.delegate),
        'numHands': o.numHands,
        'detectionConfidence': o.minHandDetectionConfidence,
        'presenceConfidence': o.minHandPresenceConfidence,
        'trackingConfidence': o.minTrackingConfidence,
        'canned': _classifier(o.cannedGesturesClassifierOptions),
        'custom': _classifier(o.customGesturesClassifierOptions),
      },
      _gesture,
      VisionTaskException.new,
    );
    holisticLandmarkerBackendFactory = (o) => AndroidVisionTask.create(
      {
        'task': 'holistic_landmarker',
        ..._base(o.modelPath, o.modelBytes, o.runningMode, o.delegate),
        'faceDetectionConfidence': o.minFaceDetectionConfidence,
        'faceSuppressionThreshold': o.minFaceSuppressionThreshold,
        'facePresenceConfidence': o.minFacePresenceConfidence,
        'handLandmarksConfidence': o.minHandLandmarksConfidence,
        'poseDetectionConfidence': o.minPoseDetectionConfidence,
        'poseSuppressionThreshold': o.minPoseSuppressionThreshold,
        'posePresenceConfidence': o.minPosePresenceConfidence,
        'blendshapes': o.outputFaceBlendshapes,
        'masks': o.outputPoseSegmentationMask,
      },
      _holistic,
      VisionTaskException.new,
    );
    faceDetectorBackendFactory = (o) => AndroidVisionTask.create(
      {
        'task': 'face_detector',
        ..._base(o.modelPath, o.modelBytes, o.runningMode, o.delegate),
        'detectionConfidence': o.minDetectionConfidence,
        'suppressionThreshold': o.minSuppressionThreshold,
      },
      _faceDetections,
      FaceDetectorException.new,
    );
    objectDetectorBackendFactory = (o) => AndroidVisionTask.create(
      {
        'task': 'object_detector',
        ..._base(o.modelPath, o.modelBytes, o.runningMode, o.delegate),
        'classifier': _limits(
          maxResults: o.maxResults,
          scoreThreshold: o.scoreThreshold,
          displayNamesLocale: o.displayNamesLocale,
          categoryAllowlist: o.categoryAllowlist,
          categoryDenylist: o.categoryDenylist,
        ),
      },
      _objectDetections,
      ObjectDetectorException.new,
    );
    imageClassifierBackendFactory = (o) => AndroidVisionTask.create(
      {
        'task': 'image_classifier',
        ..._base(o.modelPath, o.modelBytes, o.runningMode, o.delegate),
        'classifier': _limits(
          maxResults: o.maxResults,
          scoreThreshold: o.scoreThreshold,
          displayNamesLocale: o.displayNamesLocale,
          categoryAllowlist: o.categoryAllowlist,
          categoryDenylist: o.categoryDenylist,
        ),
      },
      _classifications,
      VisionTaskException.new,
    );
    imageEmbedderBackendFactory = (o) => AndroidVisionTask.create(
      {
        'task': 'image_embedder',
        ..._base(o.modelPath, o.modelBytes, o.runningMode, o.delegate),
        'l2Normalize': o.l2Normalize,
        'quantize': o.quantize,
      },
      _embeddings,
      VisionTaskException.new,
    );
    interactiveSegmenterBackendFactory = (o) async {
      try {
        final id = await _channel.invokeMethod<int>('create', {
          'task': 'interactive_segmenter',
          ..._base(
            o.modelPath,
            o.modelBytes,
            VisionRunningMode.image,
            o.delegate,
          ),
        });
        return AndroidInteractiveSegmenter._(id!);
      } on PlatformException catch (cause) {
        throw InteractiveSegmenterException(cause.message ?? cause.code);
      }
    };
    imageSegmenterBackendFactory = (o) => AndroidVisionTask.create(
      {
        'task': 'image_segmenter',
        ..._base(o.modelPath, o.modelBytes, o.runningMode, o.delegate),
        'confidenceMasks': o.outputConfidenceMasks,
        'categoryMask': o.outputCategoryMask,
        'displayNamesLocale': o.displayNamesLocale,
      },
      _segmentation,
      VisionTaskException.new,
    );
  }

  static SegmentationResult _segmentation(
    Map<String, dynamic> r,
    int? timestamp,
  ) {
    final category = r['categoryMask'] as List?;
    return SegmentationResult(
      imageWidth: r['width'] as int,
      imageHeight: r['height'] as int,
      timestampMilliseconds: timestamp,
      confidenceMasks: _masks(r['confidenceMasks'] as List?),
      categoryMask: category == null
          ? null
          : CategoryMask(
              width: category[0] as int,
              height: category[1] as int,
              categories: category[2] as Uint8List,
            ),
      qualityScores: r['qualityScores'] as Float32List?,
      labels: (r['labels'] as List).cast<String>(),
    );
  }

  /// Confidence masks sent as [width, height, Float32List] each.
  static List<SegmentationMask>? _masks(List? masks) => masks == null
      ? null
      : [
          for (final mask in masks.cast<List>())
            SegmentationMask(
              width: mask[0] as int,
              height: mask[1] as int,
              confidence: mask[2] as Float32List,
            ),
        ];

  static ImageEmbedderResult _embeddings(
    Map<String, dynamic> r,
    int? timestamp,
  ) => ImageEmbedderResult(
    imageWidth: r['width'] as int,
    imageHeight: r['height'] as int,
    timestampMilliseconds: timestamp,
    embeddings: [
      for (final head in r['embeddings'] as List)
        VisionEmbedding(
          floatEmbedding: head[0] as Float64List?,
          quantizedEmbedding: head[1] as Uint8List?,
          headIndex: head[2] as int,
          headName: _label(head[3] as String?),
        ),
    ],
  );

  static FaceDetectorResult _faceDetections(
    Map<String, dynamic> r,
    int? timestamp,
  ) => FaceDetectorResult(
    imageWidth: r['width'] as int,
    imageHeight: r['height'] as int,
    timestampMilliseconds: timestamp,
    detections: [
      for (final d in r['detections'] as List)
        FaceDetection(
          boundingBox: _box(d[0] as Float64List, FaceBoundingBox.new),
          categories: _categories(d[1] as List, FaceCategory.new),
          keypoints: [
            for (final k in d[2] as List)
              FaceKeypoint(
                x: (k[0] as num).toDouble(),
                y: (k[1] as num).toDouble(),
                label: k[2] as String?,
                score: (k[3] as num?)?.toDouble(),
              ),
          ],
        ),
    ],
  );

  static ObjectDetectorResult _objectDetections(
    Map<String, dynamic> r,
    int? timestamp,
  ) => ObjectDetectorResult(
    imageWidth: r['width'] as int,
    imageHeight: r['height'] as int,
    timestampMilliseconds: timestamp,
    detections: [
      for (final d in r['detections'] as List)
        ObjectDetection(
          boundingBox: _box(d[0] as Float64List, ObjectBoundingBox.new),
          categories: _categories(d[1] as List, ObjectCategory.new),
        ),
    ],
  );

  static ImageClassifierResult _classifications(
    Map<String, dynamic> r,
    int? timestamp,
  ) => ImageClassifierResult(
    imageWidth: r['width'] as int,
    imageHeight: r['height'] as int,
    timestampMilliseconds: timestamp,
    classifications: [
      for (final head in r['classifications'] as List)
        VisionClassifications(
          categories: _categories(head[0] as List, VisionCategory.new),
          headIndex: head[1] as int,
          headName: head[2] as String?,
        ),
    ],
  );

  /// Google's Java boxes are float pixels; the Dart boxes are whole pixels, as
  /// the C API truncates them.
  static T _box<T>(
    Float64List box,
    T Function({
      required int left,
      required int top,
      required int right,
      required int bottom,
    })
    create,
  ) => create(
    left: box[0].toInt(),
    top: box[1].toInt(),
    right: box[2].toInt(),
    bottom: box[3].toInt(),
  );

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

  static Map<String, Object?> _classifier(GestureClassifierOptions o) => {
    'maxResults': o.maxResults,
    'scoreThreshold': o.scoreThreshold,
    'displayNamesLocale': o.displayNamesLocale,
    'allowlist': o.categoryAllowlist,
    'denylist': o.categoryDenylist,
  };

  static Map<String, Object?> _base(
    String? modelPath,
    Uint8List? modelBytes,
    VisionRunningMode mode,
    VisionDelegate delegate,
  ) => {
    'modelPath': modelPath,
    'modelBytes': modelBytes,
    'mode': mode.name,
    'delegate': delegate.name,
  };

  static FaceLandmarkerResult _face(Map<String, dynamic> r, int? timestamp) =>
      FaceLandmarkerResult(
        imageWidth: r['width'] as int,
        imageHeight: r['height'] as int,
        timestampMilliseconds: timestamp,
        faceLandmarks: _landmarks(r, 'landmarks', 'counts', FaceLandmark.new),
        faceBlendshapes: [
          for (final face in r['blendshapes'] as List)
            _categories(face as List, FaceCategory.new),
        ],
        facialTransformationMatrixes: [
          for (final values in r['matrices'] as List)
            FaceTransformationMatrix(
              rows: 4,
              columns: 4,
              values: values as Float64List,
            ),
        ],
      );

  static HandLandmarkerResult _hand(Map<String, dynamic> r, int? timestamp) =>
      HandLandmarkerResult(
        imageWidth: r['width'] as int,
        imageHeight: r['height'] as int,
        timestampMilliseconds: timestamp,
        handLandmarks: _landmarks(r, 'landmarks', 'counts', VisionLandmark.new),
        handWorldLandmarks: _landmarks(
          r,
          'worldLandmarks',
          'worldCounts',
          VisionLandmark.new,
        ),
        handedness: [
          for (final hand in r['handedness'] as List)
            _categories(hand as List, VisionCategory.new),
        ],
      );

  static PoseLandmarkerResult _pose(Map<String, dynamic> r, int? timestamp) =>
      PoseLandmarkerResult(
        imageWidth: r['width'] as int,
        imageHeight: r['height'] as int,
        timestampMilliseconds: timestamp,
        poseLandmarks: _landmarks(r, 'landmarks', 'counts', VisionLandmark.new),
        poseWorldLandmarks: _landmarks(
          r,
          'worldLandmarks',
          'worldCounts',
          VisionLandmark.new,
        ),
        segmentationMasks: _masks(r['masks'] as List?),
      );

  static GestureRecognizerResult _gesture(
    Map<String, dynamic> r,
    int? timestamp,
  ) => GestureRecognizerResult(
    imageWidth: r['width'] as int,
    imageHeight: r['height'] as int,
    timestampMilliseconds: timestamp,
    handLandmarks: _landmarks(r, 'landmarks', 'counts', VisionLandmark.new),
    handWorldLandmarks: _landmarks(
      r,
      'worldLandmarks',
      'worldCounts',
      VisionLandmark.new,
    ),
    handedness: [
      for (final hand in r['handedness'] as List)
        _categories(hand as List, VisionCategory.new),
    ],
    gestures: [
      for (final hand in r['gestures'] as List)
        [
          // Canned and custom labels are numbered independently, so the
          // merged index carries no meaning; the native bindings report -1.
          for (final gesture in _categories(hand as List, VisionCategory.new))
            VisionCategory(
              index: -1,
              score: gesture.score,
              categoryName: gesture.categoryName,
              displayName: gesture.displayName,
            ),
        ],
    ],
  );

  static HolisticLandmarkerResult _holistic(
    Map<String, dynamic> r,
    int? timestamp,
  ) {
    List<VisionLandmark> part(String name) =>
        _landmarks(r, name, '${name}Counts', VisionLandmark.new).single;
    final blendshapes = r['blendshapes'] as List?;
    return HolisticLandmarkerResult(
      imageWidth: r['width'] as int,
      imageHeight: r['height'] as int,
      timestampMilliseconds: timestamp,
      faceLandmarks: part('face'),
      poseLandmarks: part('pose'),
      poseWorldLandmarks: part('poseWorld'),
      leftHandLandmarks: part('leftHand'),
      leftHandWorldLandmarks: part('leftHandWorld'),
      rightHandLandmarks: part('rightHand'),
      rightHandWorldLandmarks: part('rightHandWorld'),
      faceBlendshapes: blendshapes == null
          ? null
          : _categories(blendshapes, VisionCategory.new),
      poseSegmentationMask: switch (r['mask']) {
        final List mask => _masks([mask])!.single,
        _ => null,
      },
    );
  }

  static List<List<T>> _landmarks<T>(
    Map<String, dynamic> result,
    String values,
    String counts,
    LandmarkBuilder<T> point,
  ) => unpackLandmarks(
    result[values] as Float64List,
    result[counts] as Int32List,
    point,
  );

  // Google's Java SDK reports an unlabeled category as an empty name; its C,
  // Python and iOS APIs report none, as the Dart API does.
  static List<T> _categories<T>(List raw, CategoryBuilder<T> category) => [
    for (final c in raw)
      category(
        index: c[0] as int,
        score: (c[1] as num).toDouble(),
        categoryName: _label(c[2] as String?),
        displayName: _label(c[3] as String?),
      ),
  ];

  static String? _label(String? value) =>
      value == null || value.isEmpty ? null : value;
}

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
      throw InteractiveSegmenterException(cause.message ?? cause.code);
    }
  }

  @override
  Future<void> setImage(VisionImage image) =>
      _call<void>('setImage', _imageArguments(image));

  @override
  Future<SegmentationMask> segment(List<SegmentationStroke> strokes) async {
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
    final [width as int, height as int, values] = result['mask'] as List;
    return SegmentationMask(
      width: width,
      height: height,
      confidence: switch (values) {
        final Float32List floats => floats,
        final Uint8List bytes => Float32List.fromList([
          for (final v in bytes) v / 255,
        ]),
        _ => throw StateError('Unexpected mask values'),
      },
    );
  }

  @override
  Future<void> dispose() => _call<void>('close', const {});
}

/// One official Android SDK task on the plugin's worker thread.
final class AndroidVisionTask<R> implements VisionTaskBackend<R> {
  AndroidVisionTask._(this._id, this._decode, this._error);
  final int _id;
  final R Function(Map<String, dynamic> result, int? timestamp) _decode;
  final Exception Function(String message) _error;

  /// Creates the task named by `arguments['task']` on the plugin's worker.
  static Future<AndroidVisionTask<R>> create<R>(
    Map<String, Object?> arguments,
    R Function(Map<String, dynamic> result, int? timestamp) decode,
    Exception Function(String message) error,
  ) async {
    try {
      final id = await _channel.invokeMethod<int>('create', arguments);
      return AndroidVisionTask._(id!, decode, error);
    } on PlatformException catch (cause) {
      throw error(cause.message ?? cause.code);
    }
  }

  @override
  Future<R> detect(
    VisionImage image,
    int rotationDegrees,
    int? timestampMilliseconds, {
    VisionRegionOfInterest? regionOfInterest,
    SegmentationPoint? keypoint,
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
      throw _error(cause.message ?? cause.code);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('close', {'id': _id});
    } on PlatformException catch (cause) {
      throw _error(cause.message ?? cause.code);
    }
  }
}
