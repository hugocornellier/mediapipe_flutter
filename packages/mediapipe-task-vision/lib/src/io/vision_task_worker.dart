import 'dart:async';
import 'dart:isolate';

import '../interface/segmenter_task_types.dart' show SegmentationPoint;
import '../interface/vision_task_types.dart';

/// Input transported to a native task's worker without sharing native pointers.
///
/// The trailing point is the legacy Interactive Segmenter's region of interest;
/// every other task leaves it null.
typedef VisionTaskInput = (
  VisionImage,
  int,
  int?,
  VisionRegionOfInterest?,
  SegmentationPoint?,
);

/// Native owners are created, used and closed exclusively on their worker.
abstract interface class NativeVisionTask<R> {
  /// Process one input and return an owned Dart result.
  R process(VisionTaskInput input);

  /// Close idempotently, including after a failed processing call.
  void close();
}

/// Shared request ordering, timestamp validation and native task ownership.
final class VisionTaskWorker<R> {
  VisionTaskWorker._(this.runningMode) {
    _events.listen(_receive);
  }
  final _events = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, Completer<R?>>{};
  SendPort? _commands;
  var _nextId = 0;
  var _disposing = false;
  Future<void>? _disposal;
  VisionTaskException? _failure;
  int? _lastTimestamp;

  /// Mode selected at initialization.
  final VisionRunningMode runningMode;

  /// Construct the native owner from a top-level factory on a new isolate.
  static Future<VisionTaskWorker<R>> create<R, O extends VisionModelOptions>(
    O options,
    NativeVisionTask<R> Function(O) factory,
    String name,
  ) async {
    final worker = VisionTaskWorker<R>._(options.runningMode);
    try {
      await Isolate.spawn(
        _runWorker<R, O>,
        (worker._events.sendPort, options, factory),
        onError: worker._events.sendPort,
        onExit: worker._events.sendPort,
        debugName: name,
      );
    } catch (error, stack) {
      worker._events.close();
      Error.throwWithStackTrace(error, stack);
    }
    await worker._ready.future;
    return worker;
  }

  /// Validate a still-image request before sending it to the native worker.
  Future<R> processImage(
    VisionImage image,
    int rotation,
    VisionRegionOfInterest? region, {
    SegmentationPoint? keypoint,
  }) async {
    _check(VisionRunningMode.image, rotation);
    return (await _request((image, rotation, null, region, keypoint)))!;
  }

  /// Reserve strictly increasing timestamps in submission order.
  Future<R> processVideo(
    VisionImage image,
    int rotation,
    int timestamp,
    VisionRegionOfInterest? region,
  ) async {
    _check(VisionRunningMode.video, rotation);
    if (timestamp < 0 ||
        timestamp > 0x7fffffffffffffff ~/ 1000 ||
        (_lastTimestamp != null && timestamp <= _lastTimestamp!)) {
      throw ArgumentError.value(
        timestamp,
        'timestampMilliseconds',
        'Must be nonnegative, strictly increasing and fit MediaPipe timestamps',
      );
    }
    _lastTimestamp = timestamp;
    return (await _request((image, rotation, timestamp, region, null)))!;
  }

  void _check(VisionRunningMode expected, int rotation) {
    if (_disposing) throw StateError('Vision task has been disposed.');
    if (_failure case final error?) throw error;
    if (runningMode != expected) {
      throw StateError('This method requires ${expected.name} mode.');
    }
    if (rotation % 90 != 0 || rotation < -0x80000000 || rotation > 0x7fffffff) {
      throw ArgumentError.value(
        rotation,
        'rotationDegrees',
        'Must be a C int divisible by 90',
      );
    }
  }

  Future<R?> _request(VisionTaskInput? input) {
    final id = _nextId++;
    final completion = Completer<R?>();
    _pending[id] = completion;
    _commands!.send((id, input));
    return completion.future;
  }

  /// Reject new work immediately and drain queued requests before shutdown.
  Future<void> dispose() {
    _disposing = true;
    return _disposal ??= _close();
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
      case (int id, Object? result, VisionTaskException? error):
        final completion = _pending.remove(id);
        if (error != null) {
          completion?.completeError(error);
        } else {
          completion?.complete(result as R?);
        }
      case VisionTaskException error:
        _fail(error);
      case List<dynamic> error:
        _fail(VisionTaskException('Worker failed: ${error.join('\n')}'));
      case null:
        if (!_ready.isCompleted || _pending.isNotEmpty || !_disposing) {
          _fail(
            const VisionTaskException(
              'Native vision worker exited unexpectedly.',
            ),
          );
        }
        _events.close();
        _exited.complete();
    }
  }

  void _fail(VisionTaskException error) {
    _failure ??= error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completion in _pending.values) {
      completion.completeError(error);
    }
    _pending.clear();
  }
}

Future<void> _runWorker<R, O extends VisionModelOptions>(
  (SendPort, O, NativeVisionTask<R> Function(O)) initial,
) async {
  final (parent, options, factory) = initial;
  final commands = ReceivePort();
  NativeVisionTask<R>? native;
  try {
    native = factory(options);
    parent.send(commands.sendPort);
    await for (final dynamic message in commands) {
      final (id, input) = message as (int, VisionTaskInput?);
      R? result;
      VisionTaskException? failure;
      try {
        if (input == null) {
          native.close();
        } else {
          result = native.process(input);
        }
      } catch (error) {
        failure = error is VisionTaskException
            ? error
            : VisionTaskException(error.toString());
      }
      parent.send((id, result, failure));
      if (input == null) break;
    }
  } catch (error) {
    parent.send(
      error is VisionTaskException
          ? error
          : VisionTaskException(error.toString()),
    );
  } finally {
    try {
      native?.close();
    } finally {
      commands.close();
    }
  }
}
