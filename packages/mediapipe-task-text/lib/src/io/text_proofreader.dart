import 'dart:async';
import 'dart:isolate';

import '../interface/text_proofreader_types.dart';
import 'native_text_proofreader.dart';

/// Official Proofreader inference and streaming on a persistent worker.
///
/// Enable `mediapipe_flutter_core.tasks_runtime: true` in app hook settings.
/// Requests are serialized. Await [dispose] to drain native work and exit.
final class TextProofreader {
  TextProofreader._(this.delegate) {
    _events.listen(_receive);
  }

  /// Backend fixed at creation.
  final TextDelegate delegate;
  final _events = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, _Request>{};
  SendPort? _commands;
  int _nextId = 0;
  bool _disposing = false;
  Future<void>? _disposeFuture;
  TextProofreaderException? _failure;

  /// Load the official model off the calling isolate.
  static Future<TextProofreader> create(TextProofreaderOptions options) async {
    final task = TextProofreader._(options.delegate);
    try {
      await Isolate.spawn(
        _worker,
        (task._events.sendPort, options),
        onError: task._events.sendPort,
        onExit: task._events.sendPort,
        debugName: 'MediaPipe TextProofreader',
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

  /// Correct text and return Google's completed text and granular edits.
  Future<TextProofreaderResult> proofread(String text) async {
    _check(text);
    final request = _Request();
    final id = _nextId++;
    _pending[id] = request;
    _commands!.send((id, text, false));
    return (await request.result.future)!;
  }

  /// Start on listen and forward Google's owned chunk/correction updates.
  ///
  /// The stream has one subscription. Cancellation suppresses further delivery
  /// and waits for native completion: Google's API has no inference cancel call.
  /// Pausing buffers Dart events; it does not pause native generation.
  Stream<TextProofreaderUpdate> proofreadStream(String text) {
    _check(text);
    late StreamController<TextProofreaderUpdate> controller;
    _Request? request;
    controller = StreamController<TextProofreaderUpdate>(
      onListen: () {
        try {
          _check(text);
          final active = request = _Request(updates: controller);
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
    if (_disposing) throw StateError('TextProofreader has been disposed.');
    if (_failure case final error?) throw error;
    if (text.contains('\u0000')) {
      throw ArgumentError.value(text, 'text', 'Must not contain NUL.');
    }
  }

  /// Drain queued requests and active streams, then close the task exactly once.
  Future<void> dispose() {
    _disposing = true;
    return _disposeFuture ??= _close();
  }

  Future<void> _close() async {
    try {
      if (_failure == null) {
        final request = _Request();
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
      case (int id, TextProofreaderUpdate update):
        final request = _pending[id];
        if (request != null && !request.cancelled) request.updates?.add(update);
      case (
        int id,
        TextProofreaderResult? result,
        TextProofreaderException? error,
      ):
        _pending.remove(id)?.complete(result, error);
      case TextProofreaderException error:
        _fail(error);
      case List<dynamic> error:
        _fail(TextProofreaderException('Worker failed: ${error.join('\n')}'));
      case null:
        if (!_ready.isCompleted || _pending.isNotEmpty || !_disposing) {
          _fail(const TextProofreaderException('Proofreader worker exited.'));
        }
        _events.close();
        _exited.complete();
    }
  }

  void _fail(TextProofreaderException error) {
    _failure ??= error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final request in _pending.values) {
      request.complete(null, error);
    }
    _pending.clear();
  }
}

final class _Request {
  _Request({this.updates});
  final result = Completer<TextProofreaderResult?>();
  final finished = Completer<void>();
  final StreamController<TextProofreaderUpdate>? updates;
  bool cancelled = false;

  void complete(TextProofreaderResult? value, TextProofreaderException? error) {
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

Future<void> _worker((SendPort, TextProofreaderOptions) initial) async {
  final (parent, options) = initial;
  final commands = ReceivePort();
  NativeTextProofreader? task;
  try {
    task = NativeTextProofreader(options);
    parent.send(commands.sendPort);
    await for (final dynamic message in commands) {
      final (id, text, streaming) = message as (int, String?, bool);
      TextProofreaderResult? result;
      TextProofreaderException? failure;
      try {
        if (text == null) {
          task.close();
        } else if (streaming) {
          await task.stream(text, (update) {
            parent.send((id, update));
          });
        } else {
          result = task.proofread(text);
        }
      } catch (error) {
        failure = _exception(error);
      }
      parent.send((id, result, failure));
      if (text == null) break;
    }
  } catch (error) {
    parent.send(_exception(error));
  } finally {
    try {
      task?.close();
    } finally {
      commands.close();
    }
  }
}

TextProofreaderException _exception(Object error) =>
    error is TextProofreaderException
    ? error
    : TextProofreaderException(error.toString());
