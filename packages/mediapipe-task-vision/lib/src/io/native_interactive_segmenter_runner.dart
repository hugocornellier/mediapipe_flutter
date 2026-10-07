import 'dart:async';
import 'dart:isolate';

import 'package:mediapipe_core/mediapipe_core.dart';

import '../types/options.dart';
import '../types/strokes.dart';
import '../types/vision_types.dart';
import '../vision_task_backend.dart';
import 'native_interactive_segmenter.dart';

/// Google's stateful MagicTouch segmenter on a persistent worker isolate:
/// the image and stroke histories travel to the worker in submission order,
/// where Google's vision library keeps the session.
final class NativeInteractiveSegmenterRunner
    implements InteractiveSegmenterBackend {
  NativeInteractiveSegmenterRunner._() {
    _events.listen(_receive);
  }
  final _events = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, Completer<ConfidenceMask?>>{};
  SendPort? _commands;
  int _nextId = 0;
  bool _disposing = false;
  Future<void>? _disposeFuture;
  TaskException? _failure;

  /// Loads the task bundle off the calling isolate.
  static Future<NativeInteractiveSegmenterRunner> open(
    InteractiveSegmenterOptions options,
  ) async {
    final runner = NativeInteractiveSegmenterRunner._();
    try {
      await Isolate.spawn(
        _runWorker,
        (runner._events.sendPort, options),
        onError: runner._events.sendPort,
        onExit: runner._events.sendPort,
        debugName: 'MediaPipe Interactive Segmenter',
      );
    } catch (error, stack) {
      runner._events.close();
      Error.throwWithStackTrace(error, stack);
    }
    await runner._ready.future;
    return runner;
  }

  @override
  Future<void> setImage(VisionImage image) async {
    _checkOpen();
    await _request(image);
  }

  @override
  Future<ConfidenceMask> segment(List<Stroke> strokes) async {
    _checkOpen();
    return (await _request(strokes))!;
  }

  void _checkOpen() {
    if (_disposing) throw StateError('InteractiveSegmenter has been disposed.');
    if (_failure case final failure?) throw failure;
  }

  Future<ConfidenceMask?> _request(Object? input) {
    final id = _nextId++;
    final completer = Completer<ConfidenceMask?>();
    _pending[id] = completer;
    _commands!.send((id, input));
    return completer.future;
  }

  @override
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
      case (int id, ConfidenceMask? result, TaskException? error):
        final completer = _pending.remove(id);
        if (error != null) {
          completer?.completeError(error);
        } else {
          completer?.complete(result);
        }
      case TaskException error:
        _fail(error);
      case List<dynamic> error:
        _fail(TaskException('Worker failed: ${error.join('\n')}'));
      case null:
        if (!_ready.isCompleted || _pending.isNotEmpty || !_disposing) {
          _fail(const TaskException('Interactive Segmenter worker exited.'));
        }
        _events.close();
        _exited.complete();
    }
  }

  void _fail(TaskException error) {
    _failure ??= error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
  }
}

Future<void> _runWorker((SendPort, InteractiveSegmenterOptions) initial) async {
  final (parent, options) = initial;
  final commands = ReceivePort();
  InteractiveSegmenterSession? native;
  try {
    native = NativeInteractiveSegmenter(options);
    parent.send(commands.sendPort);
    await for (final dynamic message in commands) {
      final (id, input) = message as (int, Object?);
      ConfidenceMask? result;
      TaskException? failure;
      try {
        switch (input) {
          case null:
            native.close();
          case VisionImage image:
            native.setImage(image);
          case List<Stroke> strokes:
            result = native.segment(strokes);
          default:
            throw StateError('Unknown segmenter command.');
        }
      } catch (error) {
        failure = error is TaskException
            ? error
            : TaskException(error.toString());
      }
      parent.send((id, result, failure));
      if (input == null) break;
    }
  } catch (error) {
    parent.send(
      error is TaskException ? error : TaskException(error.toString()),
    );
  } finally {
    try {
      native?.close();
    } finally {
      commands.close();
    }
  }
}
