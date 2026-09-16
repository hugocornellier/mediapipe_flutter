import 'dart:async';
import 'dart:isolate';

import '../interface/object_detector_types.dart';
import 'native_object_detector.dart';

/// Official MediaPipe Object Detector, with inference serialized on a worker isolate.
///
/// Supports CPU/Metal on macOS arm64. Both IMAGE and VIDEO modes are supported.
/// Metal requires a float model; the pinned EfficientDet-Lite0 float32 model in
/// `models.dart` is one. Await [dispose].
final class ObjectDetector {
  ObjectDetector._(this.runningMode, this.delegate) {
    _events.listen(_receive);
  }

  final _events = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, Completer<ObjectDetectorResult?>>{};
  SendPort? _commands;
  int _nextId = 0;
  bool _disposing = false;
  Future<void>? _disposeFuture;
  ObjectDetectorException? _failure;
  int? _lastTimestamp;

  /// The official running mode selected when this detector was created.
  final VisionRunningMode runningMode;

  /// The backend requested at creation. Fixed for the lifetime of this task.
  final VisionDelegate delegate;

  /// Load an official model and initialize MediaPipe off the calling isolate.
  static Future<ObjectDetector> create(ObjectDetectorOptions options) async {
    final detector = ObjectDetector._(options.runningMode, options.delegate);
    try {
      await Isolate.spawn(
        _runWorker,
        (detector._events.sendPort, options),
        onError: detector._events.sendPort,
        onExit: detector._events.sendPort,
        debugName: 'MediaPipe Object Detector',
      );
    } catch (error, stack) {
      detector._events.close();
      // No worker was started; no futures have listeners yet.
      Error.throwWithStackTrace(error, stack);
    }
    await detector._ready.future;
    return detector;
  }

  /// Detect objects with MediaPipe's own preprocessing, inference, and suppression.
  ///
  /// [rotationDegrees] is clockwise, must be a multiple of 90, and is applied by
  /// MediaPipe. Output coordinates remain relative to the input image.
  Future<ObjectDetectorResult> detectImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) async {
    _checkMode(VisionRunningMode.image);
    _checkRotation(rotationDegrees);
    return (await _request((image, rotationDegrees, null)))!;
  }

  /// Process a video or camera frame on the inference worker.
  ///
  /// Requires [VisionRunningMode.video]. Timestamps are nonnegative milliseconds
  /// and must strictly increase in submission order. A submitted timestamp is
  /// reserved even if that frame fails. Each call returns its input timestamp.
  /// For a live camera, await each call and skip frames while busy to bound delay.
  Future<ObjectDetectorResult> detectForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) async {
    _checkMode(VisionRunningMode.video);
    _checkRotation(rotationDegrees);
    // MediaPipe converts milliseconds to signed 64-bit microseconds internally.
    if (timestampMilliseconds < 0 ||
        timestampMilliseconds > 0x7fffffffffffffff ~/ 1000 ||
        (_lastTimestamp != null && timestampMilliseconds <= _lastTimestamp!)) {
      throw ArgumentError.value(
        timestampMilliseconds,
        'timestampMilliseconds',
        'Must be nonnegative, strictly increasing, and fit MediaPipe timestamps',
      );
    }
    _lastTimestamp = timestampMilliseconds;
    return (await _request((image, rotationDegrees, timestampMilliseconds)))!;
  }

  void _checkMode(VisionRunningMode expected) {
    if (_disposing) throw StateError('ObjectDetector has been disposed.');
    if (_failure case final failure?) throw failure;
    if (runningMode != expected) {
      throw StateError(
        'This method requires ${expected.name} mode; '
        'the detector was created in ${runningMode.name} mode.',
      );
    }
  }

  void _checkRotation(int rotationDegrees) {
    if (rotationDegrees % 90 != 0 ||
        rotationDegrees < -0x80000000 ||
        rotationDegrees > 0x7fffffff) {
      throw ArgumentError.value(
        rotationDegrees,
        'rotationDegrees',
        'Must be a C int divisible by 90',
      );
    }
  }

  Future<ObjectDetectorResult?> _request((VisionImage, int, int?)? input) {
    final id = _nextId++;
    final completer = Completer<ObjectDetectorResult?>();
    _pending[id] = completer;
    _commands!.send((id, input));
    return completer.future;
  }

  /// Finish queued requests, close the native task, and stop its worker.
  ///
  /// Repeated calls return the same completion. New detections are rejected as
  /// soon as disposal starts.
  Future<void> dispose() {
    _disposing = true;
    return _disposeFuture ??= _close();
  }

  Future<void> _close() async {
    try {
      if (_failure == null) await _request(null);
    } finally {
      await _exited.future;
    }
  }

  void _receive(dynamic event) {
    switch (event) {
      case SendPort port:
        _commands = port;
        _ready.complete();
      case (
        int id,
        ObjectDetectorResult? result,
        ObjectDetectorException? error,
      ):
        final completer = _pending.remove(id);
        if (error != null) {
          completer?.completeError(error);
        } else {
          completer?.complete(result);
        }
      case ObjectDetectorException error:
        _fail(error);
      case List<dynamic> error:
        _fail(ObjectDetectorException('Worker failed: ${error.join('\n')}'));
      case null:
        if (!_ready.isCompleted || _pending.isNotEmpty || !_disposing) {
          _fail(
            const ObjectDetectorException('Object Detector worker exited.'),
          );
        }
        _events.close();
        _exited.complete();
    }
  }

  void _fail(ObjectDetectorException error) {
    _failure ??= error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
  }
}

Future<void> _runWorker((SendPort, ObjectDetectorOptions) initial) async {
  final (parent, options) = initial;
  final commands = ReceivePort();
  NativeObjectDetector? native;
  try {
    native = NativeObjectDetector(options);
    parent.send(commands.sendPort);
    await for (final dynamic message in commands) {
      final (id, input) = message as (int, (VisionImage, int, int?)?);
      ObjectDetectorResult? result;
      ObjectDetectorException? failure;
      try {
        if (input == null) {
          native.close();
        } else {
          result = native.detect(input.$1, input.$2, timestamp: input.$3);
        }
      } catch (error) {
        failure = error is ObjectDetectorException
            ? error
            : ObjectDetectorException(error.toString());
      }
      parent.send((id, result, failure));
      if (input == null) break;
    }
  } catch (error) {
    parent.send(
      error is ObjectDetectorException
          ? error
          : ObjectDetectorException(error.toString()),
    );
  } finally {
    try {
      native?.close();
    } finally {
      commands.close();
    }
  }
}
