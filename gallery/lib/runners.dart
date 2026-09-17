import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

/// A row of the result panel.
typedef ResultRow = (String label, String value);

/// Runs one task against a sample image and describes what came back.
///
/// A task appears in the gallery only once it has a runner here, so the grid
/// never offers a tile that cannot actually run. Adding a task is adding an
/// entry to [_runners].
typedef TaskRunner = Future<List<ResultRow>> Function(
  String modelPath,
  String imagePath,
  VisionDelegate delegate,
);

TaskRunner? runnerFor(String id) => _runners[id];

String _percent(num value) => '${(value * 100).toStringAsFixed(1)}%';

Future<List<ResultRow>> _faceDetector(
  String modelPath,
  String imagePath,
  VisionDelegate delegate,
) async {
  final task = await FaceDetector.create(
    FaceDetectorOptions(delegate: delegate, modelPath: modelPath),
  );
  try {
    final result = await task.detectImage(VisionImage.fromFile(imagePath));
    final rows = <ResultRow>[
      ('Image', '${result.imageWidth} x ${result.imageHeight}'),
      ('Faces', '${result.detections.length}'),
    ];
    for (var i = 0; i < result.detections.length; i++) {
      final face = result.detections[i];
      final box = face.boundingBox;
      rows.add((
        'Face ${i + 1}',
        '${_percent(face.categories.first.score)} confident, '
            '${box.width.round()}x${box.height.round()} at '
            '(${box.left.round()}, ${box.top.round()}), '
            '${face.keypoints.length} keypoints',
      ));
    }
    return rows;
  } finally {
    await task.dispose();
  }
}

Future<List<ResultRow>> _faceLandmarker(
  String modelPath,
  String imagePath,
  VisionDelegate delegate,
) async {
  final task = await FaceLandmarker.create(
    FaceLandmarkerOptions(
      delegate: delegate,
      modelPath: modelPath,
      outputFaceBlendshapes: true,
      outputFacialTransformationMatrixes: true,
    ),
  );
  try {
    final result = await task.detectImage(VisionImage.fromFile(imagePath));
    final rows = <ResultRow>[
      ('Image', '${result.imageWidth} x ${result.imageHeight}'),
      ('Faces', '${result.faceLandmarks.length}'),
    ];
    if (result.faceLandmarks.isNotEmpty) {
      rows.add(('Landmarks', '${result.faceLandmarks.first.length} per face'));
      rows.add((
        'Transform',
        result.facialTransformationMatrixes.isEmpty
            ? 'not requested'
            : '${result.facialTransformationMatrixes.first.rows}x'
                '${result.facialTransformationMatrixes.first.columns} matrix',
      ));
      if (result.faceBlendshapes.isNotEmpty) {
        final expressions = [...result.faceBlendshapes.first]
          ..sort((a, b) => b.score.compareTo(a.score));
        rows.add(('Blendshapes', '${result.faceBlendshapes.first.length}'));
        for (final shape in expressions.take(5)) {
          rows.add((
            shape.displayName?.isNotEmpty == true
                ? shape.displayName!
                : shape.categoryName ?? 'expression',
            _percent(shape.score),
          ));
        }
      }
    }
    return rows;
  } finally {
    await task.dispose();
  }
}

const _runners = <String, TaskRunner>{
  'face_detector': _faceDetector,
  'face_landmarker': _faceLandmarker,
};
