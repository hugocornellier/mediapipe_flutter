import 'dart:async';
import 'dart:isolate';

import 'package:mediapipe_core/mediapipe_core.dart';

import '../runner/text_task_runner.dart';

/// Native owner constructed and used only inside a persistent text worker.
/// [I] is the request: the text, or the text and its format context.
abstract interface class NativeTextTask<I, R, U> {
  /// Run a completed request.
  R run(I input);

  /// Drain one native stream, including its terminal callback.
  Future<void> stream(I input, void Function(U) emit);

  /// Close once all requests have drained.
  void close();
}

/// Shared queue, stream cancellation and lifecycle for official text tasks.
final class TextTaskWorker<I extends Object, R, U>
    implements TextStreamRunner<I, R, U> {
  TextTaskWorker._(this._name) {
    _events.listen(_receive);
  }

  final String _name;
  final _events = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, _Request<R, U>>{};
  SendPort? _commands;
  int _nextId = 0;
  bool _disposing = false;
  Future<void>? _disposeFuture;
  TaskException? _failure;

  /// Factories must be sendable; callers use top-level function tear-offs.
  static Future<TextTaskWorker<I, R, U>> start<I extends Object, R, U, O>({
    required String name,
    required O options,
    required NativeTextTask<I, R, U> Function(O) create,
  }) async {
    final task = TextTaskWorker<I, R, U>._(name);
    try {
      await Isolate.spawn(
        _worker<I, R, U, O>,
        (task._events.sendPort, options, create),
        onError: task._events.sendPort,
        onExit: task._events.sendPort,
        debugName: 'MediaPipe $name',
      );
    } catch (error, stack) {
      task._events.close();
      Error.throwWithStackTrace(error, stack);
    }
    try {
      await task._ready.future;
    } catch (_) {
      await task._exited.future;
      rethrow;
    }
    return task;
  }

  /// Submit one completed request.
  @override
  Future<R> run(I input) async {
    _check();
    final request = _Request<R, U>();
    final id = _nextId++;
    _pending[id] = request;
    _commands!.send((id, input, false));
    return (await request.result.future) as R;
  }

  /// Start on listen; cancellation drops delivery and waits for native drain.
  @override
  Stream<U> stream(I input) {
    _check();
    late StreamController<U> controller;
    _Request<R, U>? request;
    controller = StreamController<U>(
      onListen: () {
        try {
          _check();
          final active = request = _Request<R, U>(updates: controller);
          final id = _nextId++;
          _pending[id] = active;
          _commands!.send((id, input, true));
        } catch (error, stack) {
          controller.addError(error, stack);
          unawaited(controller.close());
        }
      },
      onCancel: () async {
        final active = request;
        if (active == null) return;
        active.cancelled = true;
        await active.finished.future;
      },
    );
    return controller.stream;
  }

  void _check() {
    if (_disposing) throw StateError('$_name has been disposed.');
    if (_failure case final error?) throw error;
  }

  /// Drain queued requests, release the native task and wait for worker exit.
  @override
  Future<void> dispose() {
    _disposing = true;
    return _disposeFuture ??= _close();
  }

  Future<void> _close() async {
    try {
      if (_failure == null) {
        final request = _Request<R, U>();
        final id = _nextId++;
        _pending[id] = request;
        _commands!.send((id, null, false));
        await request.result.future;
      }
    } finally {
      await _exited.future;
    }
  }

  void _receive(dynamic event) {
    switch (event) {
      case SendPort port:
        _commands = port;
        _ready.complete();
      case (int id, U update):
        final request = _pending[id];
        if (request != null && !request.cancelled) request.updates?.add(update);
      case (int id, R? result, TaskException? error):
        _pending.remove(id)?.complete(result, error);
      case TaskException error:
        _fail(error);
      case List<dynamic> error:
        _fail(TaskException('Worker failed: ${error.join('\n')}'));
      case null:
        if (!_ready.isCompleted || _pending.isNotEmpty || !_disposing) {
          _fail(TaskException('$_name worker exited.'));
        }
        _events.close();
        _exited.complete();
    }
  }

  void _fail(TaskException error) {
    _failure ??= error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final request in _pending.values) {
      request.complete(null, error);
    }
    _pending.clear();
  }
}

final class _Request<R, U> {
  _Request({this.updates});
  final result = Completer<R?>();
  final finished = Completer<void>();
  final StreamController<U>? updates;
  bool cancelled = false;

  void complete(R? value, TaskException? error) {
    finished.complete();
    final stream = updates;
    if (stream != null) {
      if (error != null && !cancelled) stream.addError(error);
      unawaited(stream.close());
    } else if (error != null) {
      result.completeError(error);
    } else {
      result.complete(value);
    }
  }
}

Future<void> _worker<I extends Object, R, U, O>(
  (SendPort, O, NativeTextTask<I, R, U> Function(O)) initial,
) async {
  final (parent, options, create) = initial;
  final commands = ReceivePort();
  NativeTextTask<I, R, U>? task;
  try {
    task = create(options);
    parent.send(commands.sendPort);
    await for (final dynamic message in commands) {
      final (id, input, streaming) = message as (int, I?, bool);
      R? result;
      TaskException? failure;
      try {
        if (input == null) {
          task.close();
        } else if (streaming) {
          await task.stream(input, (update) => parent.send((id, update)));
        } else {
          result = task.run(input);
        }
      } catch (error) {
        failure = taskException(error);
      }
      parent.send((id, result, failure));
      if (input == null) break;
    }
  } catch (error) {
    parent.send(taskException(error));
  } finally {
    try {
      task?.close();
    } finally {
      commands.close();
    }
  }
}
