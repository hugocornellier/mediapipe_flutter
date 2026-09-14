import 'dart:async';
import 'dart:isolate';

/// Native owner constructed and used only inside a persistent text worker.
abstract interface class NativeTextTask<R, U> {
  /// Run a completed request.
  R run(String text);

  /// Drain one native stream, including its terminal callback.
  Future<void> stream(String text, void Function(U) emit);

  /// Close once all requests have drained.
  void close();
}

/// Shared queue, stream cancellation and lifecycle for generative text tasks.
final class TextTaskWorker<R, U, E extends Exception> {
  TextTaskWorker._(this._name, this._exception) {
    _events.listen(_receive);
  }

  final String _name;
  final E Function(Object) _exception;
  final _events = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, _Request<R, U, E>>{};
  SendPort? _commands;
  int _nextId = 0;
  bool _disposing = false;
  Future<void>? _disposeFuture;
  E? _failure;

  /// Factories must be sendable; callers use top-level function tear-offs.
  static Future<TextTaskWorker<R, U, E>> start<R, U, E extends Exception, O>({
    required String name,
    required O options,
    required NativeTextTask<R, U> Function(O) create,
    required E Function(Object) exception,
  }) async {
    final task = TextTaskWorker<R, U, E>._(name, exception);
    try {
      await Isolate.spawn(
        _worker<R, U, E, O>,
        (task._events.sendPort, options, create, exception),
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
  Future<R> run(String text) async {
    _check(text);
    final request = _Request<R, U, E>();
    final id = _nextId++;
    _pending[id] = request;
    _commands!.send((id, text, false));
    return (await request.result.future)!;
  }

  /// Start on listen; cancellation drops delivery and waits for native drain.
  Stream<U> stream(String text) {
    _check(text);
    late StreamController<U> controller;
    _Request<R, U, E>? request;
    controller = StreamController<U>(
      onListen: () {
        try {
          _check(text);
          final active = request = _Request<R, U, E>(updates: controller);
          final id = _nextId++;
          _pending[id] = active;
          _commands!.send((id, text, true));
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

  void _check(String text) {
    if (_disposing) throw StateError('$_name has been disposed.');
    if (_failure case final error?) throw error;
    if (text.contains('\u0000')) {
      throw ArgumentError.value(text, 'text', 'Must not contain NUL.');
    }
  }

  /// Drain queued requests, release the native task and wait for worker exit.
  Future<void> dispose() {
    _disposing = true;
    return _disposeFuture ??= _close();
  }

  Future<void> _close() async {
    try {
      if (_failure == null) {
        final request = _Request<R, U, E>();
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
      case (int id, R? result, E? error):
        _pending.remove(id)?.complete(result, error);
      case E error:
        _fail(error);
      case List<dynamic> error:
        _fail(_exception(StateError('Worker failed: ${error.join('\n')}')));
      case null:
        if (!_ready.isCompleted || _pending.isNotEmpty || !_disposing) {
          _fail(_exception(StateError('$_name worker exited.')));
        }
        _events.close();
        _exited.complete();
    }
  }

  void _fail(E error) {
    _failure ??= error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final request in _pending.values) {
      request.complete(null, error);
    }
    _pending.clear();
  }
}

final class _Request<R, U, E extends Exception> {
  _Request({this.updates});
  final result = Completer<R?>();
  final finished = Completer<void>();
  final StreamController<U>? updates;
  bool cancelled = false;

  void complete(R? value, E? error) {
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

Future<void> _worker<R, U, E extends Exception, O>(
  (SendPort, O, NativeTextTask<R, U> Function(O), E Function(Object)) initial,
) async {
  final (parent, options, create, exception) = initial;
  final commands = ReceivePort();
  NativeTextTask<R, U>? task;
  try {
    task = create(options);
    parent.send(commands.sendPort);
    await for (final dynamic message in commands) {
      final (id, text, streaming) = message as (int, String?, bool);
      R? result;
      E? failure;
      try {
        if (text == null) {
          task.close();
        } else if (streaming) {
          await task.stream(text, (update) => parent.send((id, update)));
        } else {
          result = task.run(text);
        }
      } catch (error) {
        failure = exception(error);
      }
      parent.send((id, result, failure));
      if (text == null) break;
    }
  } catch (error) {
    parent.send(exception(error));
  } finally {
    try {
      task?.close();
    } finally {
      commands.close();
    }
  }
}
