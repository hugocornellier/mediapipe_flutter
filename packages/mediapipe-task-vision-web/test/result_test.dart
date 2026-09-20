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
}
