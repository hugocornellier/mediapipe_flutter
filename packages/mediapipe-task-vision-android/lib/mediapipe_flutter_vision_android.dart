import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_vision/face_landmarker_backend.dart';
import 'package:mediapipe_flutter_vision/mediapipe_flutter_vision.dart';

const _channel = MethodChannel('mediapipe_flutter_vision/android');

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
  }

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

  static List<T> _categories<T>(List raw, CategoryBuilder<T> category) => [
    for (final c in raw)
      category(
        index: c[0] as int,
        score: (c[1] as num).toDouble(),
        categoryName: c[2] as String?,
        displayName: c[3] as String?,
      ),
  ];
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
