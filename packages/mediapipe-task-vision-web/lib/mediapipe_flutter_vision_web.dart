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
external JSPromise<JSString> _detect(JSNumber id, JSObject input);
@JS('mediapipeVision.close')
external JSPromise<JSAny?> _close(JSNumber id);

/// Flutter registration and asynchronous adapter for Google's official runtime.
final class WebFaceLandmarker implements FaceLandmarkerFrameBackend {
  WebFaceLandmarker._(this._id);
  final JSNumber _id;
  Future<void> _tail = Future.value();
  Future<void>? _disposing;
  static Future<void>? _loaded;

  static Future<T> _workerResult<T extends JSAny?>(JSPromise<T> promise) async {
    try {
      return await promise.toDart;
    } catch (error) {
      throw FaceLandmarkerException('$error');
    }
  }

  /// Installs the browser backend before the first public task is created.
  static void registerWith(Registrar registrar) {
    faceLandmarkerBackendFactory = create;
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
    await ready.future.timeout(const Duration(seconds: 60));
  }();

  /// Creates one official browser task with the requested CPU or GPU delegate.
  static Future<FaceLandmarkerBackend> create(
    FaceLandmarkerOptions options,
  ) async {
    await _load();
    final id = await _workerResult(
      _create(
        {
              'delegate': options.delegate.name.toUpperCase(),
              'modelBytes': options.modelBytes == null
                  ? null
                  : Uint8List.fromList(options.modelBytes!).toJS,
              'modelPath': options.modelPath == null
                  ? null
                  : Uri.base.resolve(options.modelPath!).toString(),
              'runningMode': options.runningMode.name.toUpperCase(),
              'numFaces': options.numFaces,
              'minFaceDetectionConfidence': options.minFaceDetectionConfidence,
              'minFacePresenceConfidence': options.minFacePresenceConfidence,
              'minTrackingConfidence': options.minTrackingConfidence,
              'outputFaceBlendshapes': options.outputFaceBlendshapes,
              'outputFacialTransformationMatrixes':
                  options.outputFacialTransformationMatrixes,
            }.jsify()!
            as JSObject,
      ),
    );
    return WebFaceLandmarker._(id);
  }

  Future<FaceLandmarkerResult> _submit(Map<String, Object?> input) {
    if (_disposing != null) {
      return Future.error(StateError('FaceLandmarker has been disposed.'));
    }
    final result = _tail.then((_) async {
      final json = await _workerResult(
        _detect(_id, input.jsify()! as JSObject),
      );
      return decodeWebFaceResult(
        jsonDecode(json.toDart) as Map<String, dynamic>,
      );
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<FaceLandmarkerResult> detect(
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
  Future<FaceLandmarkerResult> detectFrame(
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
    await _workerResult(_close(_id));
  });
}
