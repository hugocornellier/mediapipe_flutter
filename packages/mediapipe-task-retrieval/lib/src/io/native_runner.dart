/// Google's native Universal Embedder on its own worker isolate, so loading
/// the model, every embedding and every retrieval stay off the calling
/// isolate.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:mediapipe_core/mediapipe_core.dart';

import '../retrieval_backend.dart';
import '../types/options.dart';
import 'native_retrieval.dart';

/// Opens Google's Universal Embedder on a worker.
Future<RetrievalBackend> openNativeUniversalEmbedder(
  UniversalEmbedderOptions options,
) async {
  requireRetrievalRuntime();
  return _RetrievalWorker.start(options);
}

/// Requests in order, then one close, on a worker that owns the native
/// embedder and its retrievers.
final class _RetrievalWorker implements RetrievalBackend {
  _RetrievalWorker._() {
    _events.listen(_receive);
  }

  final _events = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, Completer<Object?>>{};
  SendPort? _commands;
  int _nextId = 0;
  Future<void>? _disposing;
  MediaPipeException? _failure;

  static Future<_RetrievalWorker> start(
    UniversalEmbedderOptions options,
  ) async {
    final worker = _RetrievalWorker._();
    try {
      await Isolate.spawn(
        _main,
        (worker._events.sendPort, options),
        onError: worker._events.sendPort,
        onExit: worker._events.sendPort,
        debugName: 'MediaPipe UniversalEmbedder',
      );
    } catch (error, stack) {
      worker._events.close();
      Error.throwWithStackTrace(error, stack);
    }
    try {
      await worker._ready.future;
    } catch (_) {
      await worker._exited.future;
      rethrow;
    }
    return worker;
  }

  @override
  Future<Object?> run(Map<String, Object?> request) {
    if (_disposing != null) {
      return Future.error(StateError('UniversalEmbedder has been disposed.'));
    }
    if (_failure case final error?) return Future.error(error);
    return _send(request);
  }

  Future<Object?> _send(Map<String, Object?>? request) {
    final result = Completer<Object?>();
    final id = _nextId++;
    _pending[id] = result;
    _commands!.send((id, request));
    return result.future;
  }

  @override
  Future<void> dispose() => _disposing ??= () async {
    try {
      if (_failure == null) await _send(null);
    } finally {
      await _exited.future;
    }
  }();

  void _receive(Object? event) {
    switch (event) {
      case SendPort port:
        _commands = port;
        _ready.complete();
      case (int id, Object? result, MediaPipeException? error):
        final pending = _pending.remove(id);
        if (error != null) {
          pending?.completeError(error);
        } else {
          pending?.complete(result);
        }
      case MediaPipeException error:
        _fail(error);
      case List<Object?> error:
        _fail(TaskException('Worker failed: ${error.join('\n')}'));
      case null:
        if (!_ready.isCompleted || _pending.isNotEmpty || _disposing == null) {
          _fail(const TaskException('UniversalEmbedder worker exited.'));
        }
        _events.close();
        _exited.complete();
    }
  }

  void _fail(MediaPipeException error) {
    _failure ??= error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
  }
}

Future<void> _main((SendPort, UniversalEmbedderOptions) initial) async {
  final (parent, options) = initial;
  final commands = ReceivePort();
  NativeUniversalEmbedder? task;
  try {
    task = NativeUniversalEmbedder(options);
    parent.send(commands.sendPort);
    await for (final message in commands) {
      final (id, request) = message as (int, Map<String, Object?>?);
      Object? result;
      MediaPipeException? failure;
      try {
        if (request == null) {
          task.close();
        } else {
          result = task.run(request);
        }
      } on MediaPipeException catch (error) {
        failure = error;
      } catch (error) {
        failure = TaskException('$error');
      }
      parent.send((id, result, failure));
      if (request == null) break;
    }
  } on MediaPipeException catch (error) {
    parent.send(error);
  } catch (error) {
    parent.send(TaskException('$error'));
  } finally {
    try {
      task?.close();
    } finally {
      commands.close();
    }
  }
}
