import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/face_landmarker_backend.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

/// Automatically registers the Android SDK backend with Flutter.
final class AndroidFaceLandmarker implements FaceLandmarkerBackend {
  AndroidFaceLandmarker._(this._id);
  static const _channel = MethodChannel('mediapipe_flutter_vision/android');
  final int _id;

  static void registerWith() {
    faceLandmarkerBackendFactory = _create;
  }

  static Future<AndroidFaceLandmarker> _create(FaceLandmarkerOptions o) async {
    try {
      final id = await _channel.invokeMethod<int>('create', {
        'modelPath': o.modelPath,
        'modelBytes': o.modelBytes,
        'mode': o.runningMode.name,
        'delegate': o.delegate.name,
        'numFaces': o.numFaces,
        'detectionConfidence': o.minFaceDetectionConfidence,
        'presenceConfidence': o.minFacePresenceConfidence,
        'trackingConfidence': o.minTrackingConfidence,
        'blendshapes': o.outputFaceBlendshapes,
        'matrices': o.outputFacialTransformationMatrixes,
      });
      return AndroidFaceLandmarker._(id!);
    } on PlatformException catch (error) {
      throw FaceLandmarkerException(error.message ?? error.code);
    }
  }

  @override
  Future<FaceLandmarkerResult> detect(
    VisionImage image,
    int rotationDegrees,
    int? timestampMilliseconds,
  ) async {
    try {
      final result = (await _channel
          .invokeMapMethod<String, dynamic>('detect', {
            'id': _id,
            'path': image.path,
            'pixels': image.pixels,
            'width': image.width,
            'height': image.height,
            'stride': image.bytesPerRow,
            'format': image.format?.name,
            'rotation': ((rotationDegrees % 360) + 360) % 360,
            'timestamp': timestampMilliseconds,
          }))!;
      return FaceLandmarkerResult(
        imageWidth: result['width'] as int,
        imageHeight: result['height'] as int,
        timestampMilliseconds: timestampMilliseconds,
        faceLandmarks: [
          for (final face in result['landmarks'] as List)
            [
              for (final p in face as List)
                FaceLandmark(
                  x: (p[0] as num).toDouble(),
                  y: (p[1] as num).toDouble(),
                  z: (p[2] as num).toDouble(),
                  visibility: (p[3] as num?)?.toDouble(),
                  presence: (p[4] as num?)?.toDouble(),
                ),
            ],
        ],
        faceBlendshapes: [
          for (final face in result['blendshapes'] as List)
            [
              for (final c in face as List)
                FaceCategory(
                  index: c[0] as int,
                  score: (c[1] as num).toDouble(),
                  categoryName: c[2] as String?,
                  displayName: c[3] as String?,
                ),
            ],
        ],
        facialTransformationMatrixes: [
          for (final m in result['matrices'] as List)
            FaceTransformationMatrix(
              rows: 4,
              columns: 4,
              values: (m as List).map((v) => (v as num).toDouble()).toList(),
            ),
        ],
      );
    } on PlatformException catch (error) {
      throw FaceLandmarkerException(error.message ?? error.code);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('close', {'id': _id});
    } on PlatformException catch (error) {
      throw FaceLandmarkerException(error.message ?? error.code);
    }
  }
}
