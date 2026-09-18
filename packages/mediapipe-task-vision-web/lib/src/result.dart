import 'package:mediapipe_flutter_vision/interface.dart';

/// Copies Google's browser results into the platform-independent Dart types.
FaceLandmarkerResult decodeWebFaceResult(Map<String, dynamic> data) {
  double number(Object? value) => (value as num).toDouble();
  final result = data['result'] as Map<String, dynamic>;
  return FaceLandmarkerResult(
    imageWidth: data['width'] as int,
    imageHeight: data['height'] as int,
    timestampMilliseconds: data['timestamp'] as int?,
    faceLandmarks: [
      for (final face in result['faceLandmarks'] as List)
        [
          for (final raw in face as List)
            FaceLandmark(
              x: number(raw['x']),
              y: number(raw['y']),
              z: number(raw['z']),
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
