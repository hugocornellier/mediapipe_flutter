import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_flutter_vision_web/src/result.dart';

void main() {
  test(
    'copies optional landmark fields, categories and column-major matrix',
    () {
      final values = List<num>.generate(16, (i) => i);
      final data = <String, dynamic>{
        'width': 640,
        'height': 480,
        'timestamp': 123,
        'result': {
          'faceLandmarks': [
            [
              {'x': -0.1, 'y': 1.2, 'z': 0, 'visibility': 0.7},
            ],
          ],
          'faceBlendshapes': [
            {
              'categories': [
                {
                  'index': 2,
                  'score': 0.5,
                  'categoryName': 'jawOpen',
                  'displayName': '',
                },
              ],
            },
          ],
          'facialTransformationMatrixes': [
            {'rows': 4, 'columns': 4, 'data': values},
          ],
        },
      };
      final result = decodeWebFaceResult(data);
      values[4] = 99;
      expect(result.imageWidth, 640);
      expect(result.timestampMilliseconds, 123);
      expect(result.faceLandmarks.single.single.x, -0.1);
      expect(result.faceLandmarks.single.single.presence, isNull);
      expect(result.faceBlendshapes.single.single.categoryName, 'jawOpen');
      expect(result.facialTransformationMatrixes.single.at(0, 1), 4);
      expect(() => result.faceLandmarks.clear(), throwsUnsupportedError);
    },
  );

  test('reads packed landmarks per face, NaN as absent', () {
    final result = decodeWebFaceResult(
      {
        'width': 640,
        'height': 480,
        'timestamp': 7,
        'counts': [1, 2],
        'result': {
          'faceLandmarks': <Object?>[],
          'faceBlendshapes': <Object?>[],
          'facialTransformationMatrixes': <Object?>[],
        },
      },
      landmarks: Float64List.fromList([
        0.1, 0.2, 0.3, double.nan, double.nan, //
        0.4, 0.5, -0.6, 0.9, 0.8, //
        0.7, 0.8, 0.9, 0, double.nan,
      ]),
    );
    expect(result.faceLandmarks.map((face) => face.length), [1, 2]);
    final first = result.faceLandmarks.first.single;
    expect([first.x, first.y, first.z], [0.1, 0.2, 0.3]);
    expect(first.visibility, isNull);
    expect(first.presence, isNull);
    final second = result.faceLandmarks.last.first;
    expect([second.z, second.visibility, second.presence], [-0.6, 0.9, 0.8]);
    expect(result.faceLandmarks.last.last.visibility, 0);
  });
}
