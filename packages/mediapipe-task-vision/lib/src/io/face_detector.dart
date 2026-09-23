import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../interface/face_detector_types.dart';
import '../../vision_task_backend.dart' show faceDetectorBackendFactory;
import '../sdk_vision_task.dart';
import 'native_face_detector.dart';

/// Official MediaPipe Face Detector, with inference serialized on a worker isolate.
///
/// Supports CPU/Metal on macOS and with the official iOS SDK adapter.
/// Source-built iOS runtimes support CPU only.
/// Both targets support IMAGE/VIDEO modes. Await [dispose].
final class FaceDetector {
  FaceDetector._(this.runningMode, this.delegate, [this._sdk]) {
    _events.listen(_receive);
    // An SDK adapter runs the task; no worker isolate reports here.
    if (_sdk != null) _events.close();
  }

  /// The registered Android SDK adapter's task, when one runs this detector.
  final SdkVisionTask<FaceDetectorResult>? _sdk;

  final _events = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, Completer<FaceDetectorResult?>>{};
  SendPort? _commands;
  int _nextId = 0;
  bool _disposing = false;
  Future<void>? _disposeFuture;
  FaceDetectorException? _failure;
  int? _lastTimestamp;

  /// The official running mode selected when this detector was created.
  final VisionRunningMode runningMode;

  /// The backend requested at creation. Fixed for the lifetime of this task.
  final VisionDelegate delegate;

  /// Load an official model and initialize MediaPipe off the calling isolate.
  static Future<FaceDetector> create(FaceDetectorOptions options) async {
    if (Platform.isAndroid && faceDetectorBackendFactory != null) {
      return FaceDetector._(
        options.runningMode,
        options.delegate,
        SdkVisionTask(
          await faceDetectorBackendFactory!(options),
          options.runningMode,
          options.delegate,
          name: 'FaceDetector',
          // MediaPipe converts milliseconds to signed 64-bit microseconds.
          maxTimestamp: 0x7fffffffffffffff ~/ 1000,
        ),
      );
    }
    final detector = FaceDetector._(options.runningMode, options.delegate);
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
    if (_sdk case final sdk?) {
      return sdk.detectImage(image, rotationDegrees: rotationDegrees);
    }
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
  Future<FaceDetectorResult> detectForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) async {
    if (_sdk case final sdk?) {
      return sdk.detectForVideo(
        image,
        timestampMilliseconds: timestampMilliseconds,
        rotationDegrees: rotationDegrees,
      );
    }
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
    if (_disposing) throw StateError('FaceDetector has been disposed.');
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

  Future<FaceDetectorResult?> _request((VisionImage, int, int?)? input) {
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
    if (_sdk case final sdk?) return sdk.dispose();
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
      final (id, input) = message as (int, (VisionImage, int, int?)?);
      FaceDetectorResult? result;
      FaceDetectorException? failure;
      try {
        if (input == null) {
          native.close();
        } else {
          result = native.detect(input.$1, input.$2, timestamp: input.$3);
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
