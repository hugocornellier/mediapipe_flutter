import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:mediapipe_flutter_vision/face_landmarker_backend.dart';
import 'package:mediapipe_flutter_vision/interface.dart';
import 'package:web/web.dart' as web;

import 'src/result.dart';

@JS('mediapipeVision.create')
external JSPromise<JSNumber> _create(JSObject options);
@JS('mediapipeVision.detect')
external JSPromise<_Detection> _detect(JSNumber id, JSObject input);

/// A worker result: JSON, plus the image landmarks packed when possible.
extension type _Detection(JSObject _) implements JSObject {
  external JSString get json;
  external JSFloat64Array? get landmarks;
}
@JS('mediapipeVision.close')
external JSPromise<JSAny?> _close(JSNumber id);

/// Flutter registration for Google's official browser runtime.
abstract final class MediaPipeVisionWeb {
  /// Installs the browser backends before the first public task is created.
  static void registerWith(Registrar registrar) {
    faceLandmarkerBackendFactory = (options) => WebVisionTask.create(
      task: 'face_landmarker',
      modelBytes: options.modelBytes,
      modelPath: options.modelPath,
      delegate: options.delegate,
      runningMode: options.runningMode,
      settings: {
        'numFaces': options.numFaces,
        'minFaceDetectionConfidence': options.minFaceDetectionConfidence,
        'minFacePresenceConfidence': options.minFacePresenceConfidence,
        'minTrackingConfidence': options.minTrackingConfidence,
        'outputFaceBlendshapes': options.outputFaceBlendshapes,
        'outputFacialTransformationMatrixes':
            options.outputFacialTransformationMatrixes,
      },
      decode: (data, landmarks) =>
          decodeWebFaceResult(data, landmarks: landmarks),
      error: FaceLandmarkerException.new,
    );
    handLandmarkerBackendFactory = (options) => WebVisionTask.create(
      task: 'hand_landmarker',
      modelBytes: options.modelBytes,
      modelPath: options.modelPath,
      delegate: options.delegate,
      runningMode: options.runningMode,
      settings: {
        'numHands': options.numHands,
        'minHandDetectionConfidence': options.minHandDetectionConfidence,
        'minHandPresenceConfidence': options.minHandPresenceConfidence,
        'minTrackingConfidence': options.minTrackingConfidence,
      },
      decode: (data, landmarks) =>
          decodeWebHandResult(data, landmarks: landmarks),
      error: VisionTaskException.new,
    );
  }
}

/// One official browser task on its own worker, with requests serialized.
final class WebVisionTask<R> implements VisionTaskFrameBackend<R> {
  WebVisionTask._(this._id, this._decode, this._error);
  final JSNumber _id;
  final R Function(Map<String, dynamic> data, Float64List? landmarks) _decode;
  final Exception Function(String message) _error;
  Future<void> _tail = Future.value();
  Future<void>? _disposing;
  static Future<void>? _loaded;

  static Future<T> _workerResult<T extends JSAny?>(
    JSPromise<T> promise,
    Exception Function(String message) error,
  ) async {
    try {
      return await promise.toDart;
    } catch (cause) {
      throw error('$cause');
    }
  }

  static Future<void> _load() => _loaded ??= () async {
    final script = web.HTMLScriptElement()
      ..src = Uri.base
          .resolve(
            'assets/packages/mediapipe_flutter_vision_web/assets/bridge.js',
          )
          .toString();
    final ready = Completer<void>();
    script.onLoad.first.then((_) => ready.complete());
    script.onError.first.then((_) {
      ready.completeError(StateError('Unable to load MediaPipe web bridge.'));
    });
    web.document.head!.append(script);
    try {
      await ready.future.timeout(const Duration(seconds: 60));
    } catch (_) {
      // A transient script failure must not poison every later create call.
      script.remove();
      _loaded = null;
      rethrow;
    }
  }();

  /// Creates one official browser [task] with the requested CPU or GPU
  /// delegate; [settings] are the task's own options, named as in Google's
  /// JavaScript API.
  static Future<WebVisionTask<R>> create<R>({
    required String task,
    required Uint8List? modelBytes,
    required String? modelPath,
    required VisionDelegate delegate,
    required VisionRunningMode runningMode,
    required Map<String, Object?> settings,
    required R Function(Map<String, dynamic> data, Float64List? landmarks)
    decode,
    required Exception Function(String message) error,
  }) async {
    await _load();
    final id = await _workerResult(
      _create(
        {
              'task': task,
              'delegate': delegate.name.toUpperCase(),
              'modelBytes': modelBytes == null
                  ? null
                  : Uint8List.fromList(modelBytes).toJS,
              'modelPath': modelPath == null
                  ? null
                  : Uri.base.resolve(modelPath).toString(),
              'runningMode': runningMode.name.toUpperCase(),
              ...settings,
            }.jsify()!
            as JSObject,
      ),
      error,
    );
    return WebVisionTask._(id, decode, error);
  }

  Future<R> _submit(Map<String, Object?> input) {
    if (_disposing != null) {
      return Future.error(StateError('MediaPipe task has been disposed.'));
    }
    final result = _tail.then((_) async {
      final detection = await _workerResult(
        _detect(_id, input.jsify()! as JSObject),
        _error,
      );
      return _decode(
        jsonDecode(detection.json.toDart) as Map<String, dynamic>,
        detection.landmarks?.toDart,
      );
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<R> detect(
    VisionImage image,
    int rotationDegrees,
    int? timestampMilliseconds,
  ) => _submit({
    'path': image.path == null
        ? null
        : Uri.base.resolve(image.path!).toString(),
    'pixels': image.pixels == null
        ? null
        : Uint8List.fromList(image.pixels!).toJS,
    'width': image.width,
    'height': image.height,
    'format': image.format?.name,
    'stride': image.bytesPerRow,
    'rotation': rotationDegrees,
    'timestamp': timestampMilliseconds,
  });

  @override
  Future<R> detectFrame(
    Object frame,
    int width,
    int height,
    int rotationDegrees,
    int timestampMilliseconds,
  ) => _submit({
    'bitmap': frame,
    'width': width,
    'height': height,
    'rotation': rotationDegrees,
    'timestamp': timestampMilliseconds,
  });

  @override
  Future<void> dispose() => _disposing ??= _tail.then((_) async {
    await _workerResult(_close(_id), _error);
  });
}
