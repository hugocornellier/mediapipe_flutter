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
      index: raw['index'] as int,
      score: _number(raw['score']),
      categoryName: raw['categoryName'] as String?,
      displayName: raw['displayName'] as String?,
    ),
];
