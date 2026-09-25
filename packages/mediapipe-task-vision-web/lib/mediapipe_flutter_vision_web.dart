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

/// A worker result: JSON, plus the image landmarks packed when possible and
/// the masks the JSON names by index.
extension type _Detection(JSObject _) implements JSObject {
  external JSString get json;
  external JSFloat64Array? get landmarks;
  external JSArray<JSArrayBuffer>? get masks;
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
    poseLandmarkerBackendFactory = (options) => WebVisionTask.create(
      task: 'pose_landmarker',
      modelBytes: options.modelBytes,
      modelPath: options.modelPath,
      delegate: options.delegate,
      runningMode: options.runningMode,
      settings: {
        'numPoses': options.numPoses,
        'minPoseDetectionConfidence': options.minPoseDetectionConfidence,
        'minPosePresenceConfidence': options.minPosePresenceConfidence,
        'minTrackingConfidence': options.minTrackingConfidence,
        'outputSegmentationMasks': options.outputSegmentationMasks,
      },
      decode: (data, landmarks) =>
          decodeWebPoseResult(data, landmarks: landmarks),
      error: VisionTaskException.new,
    );
    gestureRecognizerBackendFactory = (options) => WebVisionTask.create(
      task: 'gesture_recognizer',
      modelBytes: options.modelBytes,
      modelPath: options.modelPath,
      delegate: options.delegate,
      runningMode: options.runningMode,
      settings: {
        'numHands': options.numHands,
        'minHandDetectionConfidence': options.minHandDetectionConfidence,
        'minHandPresenceConfidence': options.minHandPresenceConfidence,
        'minTrackingConfidence': options.minTrackingConfidence,
        'cannedGesturesClassifierOptions': _classifier(
          options.cannedGesturesClassifierOptions,
        ),
        'customGesturesClassifierOptions': _classifier(
          options.customGesturesClassifierOptions,
        ),
      },
      decode: (data, landmarks) =>
          decodeWebGestureResult(data, landmarks: landmarks),
      error: VisionTaskException.new,
    );
    holisticLandmarkerBackendFactory = (options) => WebVisionTask.create(
      task: 'holistic_landmarker',
      modelBytes: options.modelBytes,
      modelPath: options.modelPath,
      delegate: options.delegate,
      runningMode: options.runningMode,
      settings: {
        'minFaceDetectionConfidence': options.minFaceDetectionConfidence,
        'minFaceSuppressionThreshold': options.minFaceSuppressionThreshold,
        'minFacePresenceConfidence': options.minFacePresenceConfidence,
        'minHandLandmarksConfidence': options.minHandLandmarksConfidence,
        'minPoseDetectionConfidence': options.minPoseDetectionConfidence,
        'minPoseSuppressionThreshold': options.minPoseSuppressionThreshold,
        'minPosePresenceConfidence': options.minPosePresenceConfidence,
        'outputFaceBlendshapes': options.outputFaceBlendshapes,
        'outputPoseSegmentationMasks': options.outputPoseSegmentationMask,
      },
      decode: (data, landmarks) =>
          decodeWebHolisticResult(data, landmarks: landmarks),
      error: VisionTaskException.new,
    );
    faceDetectorBackendFactory = (options) => WebVisionTask.create(
      task: 'face_detector',
      modelBytes: options.modelBytes,
      modelPath: options.modelPath,
      delegate: options.delegate,
      runningMode: options.runningMode,
      settings: {
        'minDetectionConfidence': options.minDetectionConfidence,
        'minSuppressionThreshold': options.minSuppressionThreshold,
      },
      decode: (data, _) => decodeWebFaceDetectorResult(data),
      error: FaceDetectorException.new,
    );
    objectDetectorBackendFactory = (options) => WebVisionTask.create(
      task: 'object_detector',
      modelBytes: options.modelBytes,
      modelPath: options.modelPath,
      delegate: options.delegate,
      runningMode: options.runningMode,
      settings: _limits(
        maxResults: options.maxResults,
        scoreThreshold: options.scoreThreshold,
        displayNamesLocale: options.displayNamesLocale,
        categoryAllowlist: options.categoryAllowlist,
        categoryDenylist: options.categoryDenylist,
      ),
      decode: (data, _) => decodeWebObjectDetectorResult(data),
      error: ObjectDetectorException.new,
    );
    imageClassifierBackendFactory = (options) => WebVisionTask.create(
      task: 'image_classifier',
      modelBytes: options.modelBytes,
      modelPath: options.modelPath,
      delegate: options.delegate,
      runningMode: options.runningMode,
      settings: _limits(
        maxResults: options.maxResults,
        scoreThreshold: options.scoreThreshold,
        displayNamesLocale: options.displayNamesLocale,
        categoryAllowlist: options.categoryAllowlist,
        categoryDenylist: options.categoryDenylist,
      ),
      decode: (data, _) => decodeWebClassifierResult(data),
      error: VisionTaskException.new,
    );
    imageEmbedderBackendFactory = (options) => WebVisionTask.create(
      task: 'image_embedder',
      modelBytes: options.modelBytes,
      modelPath: options.modelPath,
      delegate: options.delegate,
      runningMode: options.runningMode,
      settings: {
        'l2Normalize': options.l2Normalize,
        'quantize': options.quantize,
      },
      decode: (data, _) => decodeWebEmbedderResult(data),
      error: VisionTaskException.new,
    );
    interactiveSegmenterLegacyBackendFactory = (options) =>
        WebVisionTask.create(
          task: 'interactive_segmenter_legacy',
          modelBytes: options.modelBytes,
          modelPath: options.modelPath,
          delegate: options.delegate,
          runningMode: VisionRunningMode.image,
          settings: {
            'outputConfidenceMasks': options.outputConfidenceMasks,
            'outputCategoryMask': options.outputCategoryMask,
          },
          decode: (data, _) => decodeWebSegmenterResult(data),
          error: VisionTaskException.new,
        );
    interactiveSegmenterBackendFactory = (options) async =>
        _WebInteractiveSegmenter(
          await WebVisionTask.create(
            task: 'interactive_segmenter',
            modelBytes: options.modelBytes,
            modelPath: options.modelPath,
            delegate: options.delegate,
            runningMode: VisionRunningMode.image,
            settings: const {},
            decode: (data, _) => data['result'] as Map<String, dynamic>,
            error: InteractiveSegmenterException.new,
          ),
        );
    imageSegmenterBackendFactory = (options) => WebVisionTask.create(
      task: 'image_segmenter',
      modelBytes: options.modelBytes,
      modelPath: options.modelPath,
      delegate: options.delegate,
      runningMode: options.runningMode,
      settings: {
        'outputConfidenceMasks': options.outputConfidenceMasks,
        'outputCategoryMask': options.outputCategoryMask,
        'displayNamesLocale': ?options.displayNamesLocale,
      },
      decode: (data, _) => decodeWebSegmenterResult(data),
      error: VisionTaskException.new,
    );
  }

  /// Classifier limits, named as in Google's JavaScript API. A non-positive
  /// maxResults means all, which is Google's default, so it is left unset.
  static Map<String, Object?> _limits({
    required int maxResults,
    required double scoreThreshold,
    required String? displayNamesLocale,
    required List<String> categoryAllowlist,
    required List<String> categoryDenylist,
  }) => {
    if (maxResults > 0) 'maxResults': maxResults,
    'scoreThreshold': scoreThreshold,
    'displayNamesLocale': ?displayNamesLocale,
    if (categoryAllowlist.isNotEmpty) 'categoryAllowlist': categoryAllowlist,
    if (categoryDenylist.isNotEmpty) 'categoryDenylist': categoryDenylist,
  };

  /// Canned or custom gesture limits, named as in Google's JavaScript API.
  /// Google rejects a non-positive maxResults, so -1 (all) is left unset.
  static Map<String, Object?> _classifier(GestureClassifierOptions o) => {
    if (o.maxResults > 0) 'maxResults': o.maxResults,
    'scoreThreshold': o.scoreThreshold,
    'displayNamesLocale': ?o.displayNamesLocale,
    if (o.categoryAllowlist.isNotEmpty)
      'categoryAllowlist': o.categoryAllowlist,
    if (o.categoryDenylist.isNotEmpty) 'categoryDenylist': o.categoryDenylist,
  };
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
      final data = jsonDecode(detection.json.toDart) as Map<String, dynamic>;
      if (detection.masks?.toDart case final masks?) {
        attachWebMasks(data['result'] as Map<String, dynamic>, [
          for (final mask in masks) mask.toDart,
        ]);
      }
      return _decode(data, detection.landmarks?.toDart);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<R> detect(
    VisionImage image,
    int rotationDegrees,
    int? timestampMilliseconds, {
    VisionRegionOfInterest? regionOfInterest,
    SegmentationPoint? keypoint,
  }) => _submit({
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
    'region': switch (regionOfInterest) {
      final r? => [r.left, r.top, r.right, r.bottom],
      null => null,
    },
    'keypoint': switch (keypoint) {
      final k? => [k.x, k.y],
      null => null,
    },
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

/// Google's stateful MagicTouch segmenter on a worker: an image, then complete
/// stroke histories, serialized with the worker's other requests.
final class _WebInteractiveSegmenter implements InteractiveSegmenterBackend {
  _WebInteractiveSegmenter(this._task);
  final WebVisionTask<Map<String, dynamic>> _task;

  @override
  Future<void> setImage(VisionImage image) => _task.detect(image, 0, null);

  @override
  Future<SegmentationMask> segment(List<SegmentationStroke> strokes) async {
    final result = await _task._submit({
      'strokes': [
        for (final stroke in strokes)
          [
            stroke.brushMode.nativeValue,
            [
              for (final point in stroke.points) ...[point.x, point.y],
            ],
            stroke.isCompleted,
          ],
      ],
    });
    final [width as int, height as int, values as Float32List] =
        (result['confidenceMasks'] as List).single as List;
    return SegmentationMask(width: width, height: height, confidence: values);
  }

  @override
  Future<void> dispose() => _task.dispose();
}
