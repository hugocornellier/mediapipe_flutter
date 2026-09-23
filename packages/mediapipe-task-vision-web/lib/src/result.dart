import 'dart:typed_data';

import 'package:mediapipe_flutter_vision/interface.dart';
import 'package:mediapipe_flutter_vision/vision_task_backend.dart';

/// Copies Google's browser results into the platform-independent Dart types.
///
/// With [landmarks], the worker sent the face landmarks packed as x, y, z,
/// visibility, presence per point (NaN for an absent value) and
/// `data['counts']` gives the points per face; otherwise they are in the JSON.
FaceLandmarkerResult decodeWebFaceResult(
  Map<String, dynamic> data, {
  Float64List? landmarks,
}) {
  final result = data['result'] as Map<String, dynamic>;
  return FaceLandmarkerResult(
    imageWidth: data['width'] as int,
    imageHeight: data['height'] as int,
    timestampMilliseconds: data['timestamp'] as int?,
    faceLandmarks: _landmarks(
      data,
      landmarks,
      result['faceLandmarks'],
      FaceLandmark.new,
    ),
    faceBlendshapes: [
      for (final face in result['faceBlendshapes'] as List)
        _categories(face['categories'], FaceCategory.new),
    ],
    facialTransformationMatrixes: [
      for (final raw in result['facialTransformationMatrixes'] as List)
        FaceTransformationMatrix(
          rows: raw['rows'] as int,
          columns: raw['columns'] as int,
          values: [for (final value in raw['data'] as List) _number(value)],
        ),
    ],
  );
}

/// Copies a browser Hand Landmarker result; [landmarks] as for faces.
HandLandmarkerResult decodeWebHandResult(
  Map<String, dynamic> data, {
  Float64List? landmarks,
}) {
  final result = data['result'] as Map<String, dynamic>;
  return HandLandmarkerResult(
    imageWidth: data['width'] as int,
    imageHeight: data['height'] as int,
    timestampMilliseconds: data['timestamp'] as int?,
    handLandmarks: _landmarks(
      data,
      landmarks,
      result['landmarks'],
      VisionLandmark.new,
    ),
    handWorldLandmarks: _landmarks(
      data,
      null,
      result['worldLandmarks'],
      VisionLandmark.new,
    ),
    handedness: [
      for (final hand in result['handedness'] as List)
        _categories(hand, VisionCategory.new),
    ],
  );
}

/// Copies a browser Pose Landmarker result; [landmarks] as for faces.
PoseLandmarkerResult decodeWebPoseResult(
  Map<String, dynamic> data, {
  Float64List? landmarks,
}) {
  final result = data['result'] as Map<String, dynamic>;
  return PoseLandmarkerResult(
    imageWidth: data['width'] as int,
    imageHeight: data['height'] as int,
    timestampMilliseconds: data['timestamp'] as int?,
    poseLandmarks: _landmarks(
      data,
      landmarks,
      result['landmarks'],
      VisionLandmark.new,
    ),
    poseWorldLandmarks: _landmarks(
      data,
      null,
      result['worldLandmarks'],
      VisionLandmark.new,
    ),
    segmentationMasks: _confidenceMasks(result['segmentationMasks']),
  );
}

/// Copies a browser Gesture Recognizer result; [landmarks] as for faces.
GestureRecognizerResult decodeWebGestureResult(
  Map<String, dynamic> data, {
  Float64List? landmarks,
}) {
  final result = data['result'] as Map<String, dynamic>;
  return GestureRecognizerResult(
    imageWidth: data['width'] as int,
    imageHeight: data['height'] as int,
    timestampMilliseconds: data['timestamp'] as int?,
    handLandmarks: _landmarks(
      data,
      landmarks,
      result['landmarks'],
      VisionLandmark.new,
    ),
    handWorldLandmarks: _landmarks(
      data,
      null,
      result['worldLandmarks'],
      VisionLandmark.new,
    ),
    handedness: [
      for (final hand in result['handedness'] as List)
        _categories(hand, VisionCategory.new),
    ],
    gestures: [
      for (final hand in result['gestures'] as List)
        [
          // Canned and custom labels are numbered independently, so the
          // merged index carries no meaning; the native bindings report -1.
          for (final gesture in _categories(hand, VisionCategory.new))
            VisionCategory(
              index: -1,
              score: gesture.score,
              categoryName: gesture.categoryName,
              displayName: gesture.displayName,
            ),
        ],
    ],
  );
}

/// Copies a browser Holistic Landmarker result. Google's browser API lists
/// each part per subject; Holistic reports at most one.
HolisticLandmarkerResult decodeWebHolisticResult(Map<String, dynamic> data) {
  final result = data['result'] as Map<String, dynamic>;
  List<VisionLandmark> part(String name) {
    final subjects = _landmarks(data, null, result[name], VisionLandmark.new);
    return subjects.isEmpty ? const [] : subjects.first;
  }

  final blendshapes = result['faceBlendshapes'] as List?;
  return HolisticLandmarkerResult(
    imageWidth: data['width'] as int,
    imageHeight: data['height'] as int,
    timestampMilliseconds: data['timestamp'] as int?,
    faceLandmarks: part('faceLandmarks'),
    poseLandmarks: part('poseLandmarks'),
    poseWorldLandmarks: part('poseWorldLandmarks'),
    leftHandLandmarks: part('leftHandLandmarks'),
    leftHandWorldLandmarks: part('leftHandWorldLandmarks'),
    rightHandLandmarks: part('rightHandLandmarks'),
    rightHandWorldLandmarks: part('rightHandWorldLandmarks'),
    faceBlendshapes: blendshapes == null || blendshapes.isEmpty
        ? null
        : _categories(blendshapes.first['categories'], VisionCategory.new),
    poseSegmentationMask: _confidenceMasks(
      result['poseSegmentationMasks'],
    )?.firstOrNull,
  );
}

/// Copies a browser Face Detector result. Google's boxes are float pixels;
/// the Dart boxes are whole pixels, truncated as the C API does.
FaceDetectorResult decodeWebFaceDetectorResult(Map<String, dynamic> data) =>
    FaceDetectorResult(
      imageWidth: data['width'] as int,
      imageHeight: data['height'] as int,
      timestampMilliseconds: data['timestamp'] as int?,
      detections: [
        for (final d in (data['result'] as Map)['detections'] as List)
          FaceDetection(
            boundingBox: _box(d['boundingBox'], FaceBoundingBox.new),
            categories: _categories(d['categories'], FaceCategory.new),
            keypoints: [
              for (final k in (d['keypoints'] as List?) ?? const [])
                FaceKeypoint(
                  x: _number(k['x']),
                  y: _number(k['y']),
                  label: _label(k['label']),
                  score: _optional(k['score']),
                ),
            ],
          ),
      ],
    );

/// Copies a browser Object Detector result, boxes as for faces.
ObjectDetectorResult decodeWebObjectDetectorResult(Map<String, dynamic> data) =>
    ObjectDetectorResult(
      imageWidth: data['width'] as int,
      imageHeight: data['height'] as int,
      timestampMilliseconds: data['timestamp'] as int?,
      detections: [
        for (final d in (data['result'] as Map)['detections'] as List)
          ObjectDetection(
            boundingBox: _box(d['boundingBox'], ObjectBoundingBox.new),
            categories: _categories(d['categories'], ObjectCategory.new),
          ),
      ],
    );

/// Copies a browser Image Classifier result.
ImageClassifierResult decodeWebClassifierResult(Map<String, dynamic> data) =>
    ImageClassifierResult(
      imageWidth: data['width'] as int,
      imageHeight: data['height'] as int,
      timestampMilliseconds: data['timestamp'] as int?,
      classifications: [
        for (final head in (data['result'] as Map)['classifications'] as List)
          VisionClassifications(
            categories: _categories(head['categories'], VisionCategory.new),
            headIndex: head['headIndex'] as int,
            headName: _label(head['headName']),
          ),
      ],
    );

T _box<T>(
  Object? json,
  T Function({
    required int left,
    required int top,
    required int right,
    required int bottom,
  })
  create,
) {
  final box = json as Map;
  final left = _number(box['originX']), top = _number(box['originY']);
  return create(
    left: left.toInt(),
    top: top.toInt(),
    right: (left + _number(box['width'])).toInt(),
    bottom: (top + _number(box['height'])).toInt(),
  );
}

/// Copies a browser Image Embedder result: one vector per model head.
ImageEmbedderResult decodeWebEmbedderResult(Map<String, dynamic> data) =>
    ImageEmbedderResult(
      imageWidth: data['width'] as int,
      imageHeight: data['height'] as int,
      timestampMilliseconds: data['timestamp'] as int?,
      embeddings: [
        for (final head in (data['result'] as Map)['embeddings'] as List)
          VisionEmbedding(
            floatEmbedding: switch (head['floatEmbedding']) {
              final List values => [for (final v in values) _number(v)],
              _ => null,
            },
            quantizedEmbedding: switch (head['quantizedEmbedding']) {
              final List values => Uint8List.fromList(values.cast<int>()),
              _ => null,
            },
            headIndex: head['headIndex'] as int,
            headName: _label(head['headName']),
          ),
      ],
    );

/// Replaces each mask the worker named as [width, height, bytes per value,
/// index] in [result] with [width, height, values] read from [buffers]:
/// float32 confidences or uint8 categories.
void attachWebMasks(Map<String, dynamic> result, List<ByteBuffer> buffers) {
  List<Object> mask(List named) {
    final [width as int, height as int, depth as int, index as int] = named;
    final bytes = buffers[index];
    if (bytes.lengthInBytes != width * height * depth) {
      throw StateError('Mask $index has ${bytes.lengthInBytes} bytes.');
    }
    return [
      width,
      height,
      depth == 1 ? bytes.asUint8List() : bytes.asFloat32List(),
    ];
  }

  for (final key in const [
    'confidenceMasks',
    'segmentationMasks',
    'poseSegmentationMasks',
  ]) {
    if (result[key] case final List masks) {
      result[key] = [for (final named in masks) mask(named as List)];
    }
  }
  if (result['categoryMask'] case final List named) {
    result['categoryMask'] = mask(named);
  }
}

/// Copies a browser Image Segmenter result after [attachWebMasks].
SegmentationResult decodeWebSegmenterResult(Map<String, dynamic> data) {
  final result = data['result'] as Map<String, dynamic>;
  final category = result['categoryMask'] as List?;
  return SegmentationResult(
    imageWidth: data['width'] as int,
    imageHeight: data['height'] as int,
    timestampMilliseconds: data['timestamp'] as int?,
    confidenceMasks: _confidenceMasks(result['confidenceMasks']),
    categoryMask: category == null
        ? null
        : CategoryMask(
            width: category[0] as int,
            height: category[1] as int,
            categories: category[2] as Uint8List,
          ),
    qualityScores: switch (result['qualityScores']) {
      final List scores => Float32List.fromList([
        for (final score in scores) _number(score),
      ]),
      _ => null,
    },
    labels: [
      for (final label in result['labels'] as List? ?? const []) '$label',
    ],
  );
}

List<SegmentationMask>? _confidenceMasks(Object? masks) => masks is List
    ? [
        for (final mask in masks.cast<List>())
          SegmentationMask(
            width: mask[0] as int,
            height: mask[1] as int,
            confidence: mask[2] as Float32List,
          ),
      ]
    : null;

/// Google's browser API reports an absent label as an empty string.
String? _label(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

double _number(Object? value) => (value as num).toDouble();
double? _optional(Object? value) => value == null ? null : _number(value);

List<List<T>> _landmarks<T>(
  Map<String, dynamic> data,
  Float64List? packed,
  Object? json,
  LandmarkBuilder<T> point,
) {
  if (packed != null) {
    return unpackLandmarks(packed, (data['counts'] as List).cast<int>(), point);
  }
  return [
    for (final subject in json as List)
      [
        for (final raw in subject as List)
          point(
            x: _number(raw['x']),
            y: _number(raw['y']),
            z: _number(raw['z']),
            name: raw['name'] as String?,
            visibility: _optional(raw['visibility']),
            presence: _optional(raw['presence']),
          ),
      ],
  ];
}

List<T> _categories<T>(Object? json, CategoryBuilder<T> category) => [
  for (final raw in json as List)
    category(
      index: raw['index'] as int? ?? -1,
      score: _number(raw['score']),
      categoryName: _label(raw['categoryName']),
      displayName: _label(raw['displayName']),
    ),
];
