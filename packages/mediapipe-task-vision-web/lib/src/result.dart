import 'dart:typed_data';

import 'package:mediapipe_flutter_vision/interface.dart';

/// Copies Google's browser results into the platform-independent Dart types.
///
/// With [landmarks], the worker sent the face landmarks packed as x, y, z,
/// visibility, presence per point (NaN for an absent value) and
/// `data['counts']` gives the points per face; otherwise they are in the JSON.
FaceLandmarkerResult decodeWebFaceResult(
  Map<String, dynamic> data, {
  Float64List? landmarks,
}) {
  double number(Object? value) => (value as num).toDouble();
  final result = data['result'] as Map<String, dynamic>;
  return FaceLandmarkerResult(
    imageWidth: data['width'] as int,
    imageHeight: data['height'] as int,
    timestampMilliseconds: data['timestamp'] as int?,
    faceLandmarks: landmarks != null
        ? _unpack(landmarks, (data['counts'] as List).cast<int>())
        : [
            for (final face in result['faceLandmarks'] as List)
              [
                for (final raw in face as List)
                  FaceLandmark(
                    x: number(raw['x']),
                    y: number(raw['y']),
                    z: number(raw['z']),
                    name: raw['name'] as String?,
                    visibility: raw['visibility'] == null
                        ? null
                        : number(raw['visibility']),
                    presence: raw['presence'] == null
                        ? null
                        : number(raw['presence']),
                  ),
              ],
          ],
    faceBlendshapes: [
      for (final face in result['faceBlendshapes'] as List)
        [
          for (final raw in face['categories'] as List)
            FaceCategory(
              index: raw['index'] as int,
              score: number(raw['score']),
              categoryName: raw['categoryName'] as String?,
              displayName: raw['displayName'] as String?,
            ),
        ],
    ],
    facialTransformationMatrixes: [
      for (final raw in result['facialTransformationMatrixes'] as List)
        FaceTransformationMatrix(
          rows: raw['rows'] as int,
          columns: raw['columns'] as int,
          values: [for (final value in raw['data'] as List) number(value)],
        ),
    ],
  );
}

List<List<FaceLandmark>> _unpack(Float64List packed, List<int> counts) {
  double? optional(double value) => value.isNaN ? null : value;
  final faces = <List<FaceLandmark>>[];
  var at = 0;
  for (final count in counts) {
    faces.add([
      for (var point = 0; point < count; point++, at += 5)
        FaceLandmark(
          x: packed[at],
          y: packed[at + 1],
          z: packed[at + 2],
          visibility: optional(packed[at + 3]),
          presence: optional(packed[at + 4]),
        ),
    ]);
  }
  return faces;
}
