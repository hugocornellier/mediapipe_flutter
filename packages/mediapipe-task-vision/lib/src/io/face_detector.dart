import 'dart:async';
import 'dart:isolate';

import '../interface/face_detector_types.dart';
import 'native_face_detector.dart';

/// Official MediaPipe Face Detector, with inference serialized on a worker isolate.
///
/// This initial API supports CPU IMAGE mode on macOS arm64. Always await [dispose].
final class FaceDetector {
  FaceDetector._() {
    _events.listen(_receive);
  }

  final _events = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, Completer<FaceDetectorResult?>>{};
  SendPort? _commands;
  int _nextId = 0;
  bool _disposing = false;
  Future<void>? _disposeFuture;
  FaceDetectorException? _failure;

  /// Load an official model and initialize MediaPipe off the calling isolate.
  static Future<FaceDetector> create(FaceDetectorOptions options) async {
    final detector = FaceDetector._();
    try {
      await Isolate.spawn(
        _runWorker,
        (detector._events.sendPort, options),
        onError: detector._events.sendPort,
        onExit: detector._events.sendPort,
        debugName: 'MediaPipe Face Detector',
      );
    } catch (error, stack) {
      detector._events.close();
      // No worker was started; no futures have listeners yet.
      Error.throwWithStackTrace(error, stack);
    }
    await detector._ready.future;
    return detector;
  }

  /// Detect faces with MediaPipe's own preprocessing, inference, and suppression.
  ///
  /// [rotationDegrees] is clockwise, must be a multiple of 90, and is applied by
  /// MediaPipe. Output coordinates remain relative to the input image.
  Future<FaceDetectorResult> detectImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) async {
    if (_disposing) throw StateError('FaceDetector has been disposed.');
    if (_failure case final failure?) throw failure;
    if (rotationDegrees % 90 != 0 ||
        rotationDegrees < -0x80000000 ||
        rotationDegrees > 0x7fffffff) {
      throw ArgumentError.value(
        rotationDegrees,
        'rotationDegrees',
        'Must be a C int divisible by 90',
      );
    }
    return (await _request((image, rotationDegrees)))!;
  }

  Future<FaceDetectorResult?> _request((VisionImage, int)? input) {
    final id = _nextId++;
    final completer = Completer<FaceDetectorResult?>();
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
      case (int id, FaceDetectorResult? result, FaceDetectorException? error):
        final completer = _pending.remove(id);
        if (error != null) {
          completer?.completeError(error);
        } else {
          completer?.complete(result);
        }
      case FaceDetectorException error:
        _fail(error);
      case List<dynamic> error:
        _fail(FaceDetectorException('Worker failed: ${error.join('\n')}'));
      case null:
        if (!_ready.isCompleted || _pending.isNotEmpty || !_disposing) {
          _fail(const FaceDetectorException('Face Detector worker exited.'));
        }
        _events.close();
        _exited.complete();
    }
  }

  void _fail(FaceDetectorException error) {
    _failure ??= error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
  }
}

Future<void> _runWorker((SendPort, FaceDetectorOptions) initial) async {
  final (parent, options) = initial;
  final commands = ReceivePort();
  NativeFaceDetector? native;
  try {
    native = NativeFaceDetector(options);
    parent.send(commands.sendPort);
    await for (final dynamic message in commands) {
      final (id, input) = message as (int, (VisionImage, int)?);
      FaceDetectorResult? result;
      FaceDetectorException? failure;
      try {
        if (input == null) {
          native.close();
        } else {
          result = native.detect(input.$1, input.$2);
        }
      } catch (error) {
        failure = error is FaceDetectorException
            ? error
            : FaceDetectorException(error.toString());
      }
      parent.send((id, result, failure));
      if (input == null) break;
    }
  } catch (error) {
    parent.send(
      error is FaceDetectorException
          ? error
          : FaceDetectorException(error.toString()),
    );
  } finally {
    try {
      native?.close();
    } finally {
      commands.close();
    }
  }
}
