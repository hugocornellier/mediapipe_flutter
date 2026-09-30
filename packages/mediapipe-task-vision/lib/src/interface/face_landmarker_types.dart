import 'face_detector_types.dart';
import 'vision_task_types.dart';

export 'vision_task_types.dart' show VisionTaskException;

/// Configuration of the official Face Landmarker task.
final class FaceLandmarkerOptions extends VisionModelOptions {
  /// Supply exactly one model source. Defaults match Google's task API.
  FaceLandmarkerOptions({
    super.model,
    super.modelPath,
    super.modelBytes,
    super.runningMode,
    super.delegate,
    this.numFaces = 1,
    this.minFaceDetectionConfidence = 0.5,
    this.minFacePresenceConfidence = 0.5,
    this.minTrackingConfidence = 0.5,
    this.outputFaceBlendshapes = false,
    this.outputFacialTransformationMatrixes = false,
  }) {
    if (numFaces < 1 || numFaces > 0x7fffffff) {
      throw ArgumentError.value(
        numFaces,
        'numFaces',
        'Must be a positive C int',
      );
    }
    for (final entry in {
      'minFaceDetectionConfidence': minFaceDetectionConfidence,
      'minFacePresenceConfidence': minFacePresenceConfidence,
      'minTrackingConfidence': minTrackingConfidence,
    }.entries) {
      if (!entry.value.isFinite || entry.value < 0 || entry.value > 1) {
        throw ArgumentError.value(entry.value, entry.key, 'Must be in [0, 1]');
      }
    }
  }

  /// Maximum number of faces. Official video smoothing applies only at 1.
  final int numFaces;

  /// Minimum face detection confidence.
  final double minFaceDetectionConfidence;

  /// Minimum face presence confidence.
  final double minFacePresenceConfidence;

  /// Minimum face tracking confidence.
  final double minTrackingConfidence;

  /// Include the official model's 52 expression scores for each face.
  final bool outputFaceBlendshapes;

  /// Include the official canonical-face-to-detected-face transform.
  final bool outputFacialTransformationMatrixes;
}

/// An unmodified normalized 3D landmark from MediaPipe.
final class FaceLandmark {
  /// Copies a landmark without clipping, smoothing, or reordering coordinates.
  const FaceLandmark({
    required this.x,
    required this.y,
    required this.z,
    this.visibility,
    this.presence,
    this.name,
  });

  /// Horizontal coordinate relative to input width; may extend outside [0, 1].
  final double x;

  /// Vertical coordinate relative to input height; may extend outside [0, 1].
  final double y;

  /// Relative depth, scaled like x. Smaller values are closer to the camera.
  /// This is not a distance in meters.
  final double z;

  /// Optional visibility, absent when the model does not provide it.
  final double? visibility;

  /// Optional presence, absent when the model does not provide it.
  final double? presence;

  /// Optional model-provided name.
  final String? name;
}

/// A copied native matrix, retaining the official C API's column-major layout.
final class FaceTransformationMatrix {
  /// Stores an immutable copy of the matrix data.
  FaceTransformationMatrix({
    required this.rows,
    required this.columns,
    required List<double> values,
  }) : values = List.unmodifiable(values) {
    if (rows <= 0 || columns <= 0 || values.length != rows * columns) {
      throw ArgumentError('Matrix dimensions must match the data.');
    }
  }

  /// Row count; 4 for the official face transform.
  final int rows;

  /// Column count; 4 for the official face transform.
  final int columns;

  /// Column-major data: element (row, column) is column * rows + row.
  final List<double> values;

  /// Read a matrix element with bounds checking.
  double at(int row, int column) {
    RangeError.checkValueInInterval(row, 0, rows - 1, 'row');
    RangeError.checkValueInInterval(column, 0, columns - 1, 'column');
    return values[column * rows + row];
  }
}

/// Results owned by Dart, valid after later frames and task disposal.
final class FaceLandmarkerResult {
  /// Copies all result lists, preserving MediaPipe's face and landmark ordering.
  FaceLandmarkerResult({
    required this.imageWidth,
    required this.imageHeight,
    required List<List<FaceLandmark>> faceLandmarks,
    required List<List<FaceCategory>> faceBlendshapes,
    required List<FaceTransformationMatrix> facialTransformationMatrixes,
    this.timestampMilliseconds,
  }) : faceLandmarks = List.unmodifiable(
         faceLandmarks.map((face) => List<FaceLandmark>.unmodifiable(face)),
       ),
       faceBlendshapes = List.unmodifiable(
         faceBlendshapes.map((face) => List<FaceCategory>.unmodifiable(face)),
       ),
       facialTransformationMatrixes = List.unmodifiable(
         facialTransformationMatrixes,
       );

  /// Decoded input width, after any EXIF orientation correction.
  final int imageWidth;

  /// Decoded input height, after any EXIF orientation correction.
  final int imageHeight;

  /// 478 landmarks per face from the official bundle, including both irises.
  final List<List<FaceLandmark>> faceLandmarks;

  /// Expression scores in native order. Empty when disabled or no face is found.
  final List<List<FaceCategory>> faceBlendshapes;

  /// One matrix per face. Empty when disabled or no face is found.
  final List<FaceTransformationMatrix> facialTransformationMatrixes;

  /// Input video timestamp, or null in IMAGE mode.
  final int? timestampMilliseconds;
}
