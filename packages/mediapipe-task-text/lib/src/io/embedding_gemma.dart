import 'dart:async';
import 'dart:isolate';

import '../interface/embedding_gemma_types.dart';
import 'native_embedding_gemma.dart';

/// Official EmbeddingGemma pipeline on a persistent inference worker.
///
/// Enable `mediapipe_flutter_core.tasks_runtime: true` in build-hook settings.
/// Currently supports macOS arm64 CPU, macOS 14+. Await [dispose] when finished.
final class EmbeddingGemma {
  EmbeddingGemma._(this.delegate) {
    _events.listen(_receive);
  }

  /// Backend fixed at creation; no automatic fallback.
  final TextDelegate delegate;
  final _events = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, Completer<TextEmbeddingResult?>>{};
  SendPort? _commands;
  int _nextId = 0;
  bool _disposing = false;
  Future<void>? _disposeFuture;
  EmbeddingGemmaException? _failure;

  /// Load the model off the calling isolate. Initialization failures complete
  /// this future with an error, including a missing runtime or invalid model.
  static Future<EmbeddingGemma> create(EmbeddingGemmaOptions options) async {
    final task = EmbeddingGemma._(options.delegate);
    try {
      await Isolate.spawn(
        _runWorker,
        (task._events.sendPort, options),
        onError: task._events.sendPort,
        onExit: task._events.sendPort,
        debugName: 'MediaPipe EmbeddingGemma',
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

  /// Embed text using Google's optional formatting context.
  ///
  /// Calls are serialized in submission order. No Dart tokenization, truncation
  /// or normalization is added. The official model rejects overlong inputs;
  /// after a native graph failure, dispose and create a new task.
  Future<TextEmbeddingResult> embed(
    String text, {
    TextFormatContext? context,
  }) async {
    if (_disposing) throw StateError('EmbeddingGemma has been disposed.');
    if (_failure case final error?) throw error;
    if (text.contains('\u0000')) {
      throw ArgumentError.value(text, 'text', 'Must not contain NUL.');
    }
    return (await _request((text, context)))!;
  }

  Future<TextEmbeddingResult?> _request(Object? input) {
    final id = _nextId++;
    final completer = Completer<TextEmbeddingResult?>();
    _pending[id] = completer;
    _commands!.send((id, input));
    return completer.future;
  }

  /// Drain queued work and release the native task and worker exactly once.
  /// A failed graph's native close error is reported after the worker exits.
  /// Cleanup inside Google's runtime is not guaranteed when native close fails.
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
        TextEmbeddingResult? result,
        EmbeddingGemmaException? error,
      ):
        final completer = _pending.remove(id);
        if (error != null) {
          completer?.completeError(error);
        } else {
          completer?.complete(result);
        }
      case EmbeddingGemmaException error:
        _fail(error);
      case List<dynamic> error:
        _fail(EmbeddingGemmaException('Worker failed: ${error.join('\n')}'));
      case null:
        if (!_ready.isCompleted || _pending.isNotEmpty || !_disposing) {
          _fail(const EmbeddingGemmaException('EmbeddingGemma worker exited.'));
        }
        _events.close();
        _exited.complete();
    }
  }

  void _fail(EmbeddingGemmaException error) {
    _failure ??= error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
  }
}

Future<void> _runWorker((SendPort, EmbeddingGemmaOptions) initial) async {
  final (parent, options) = initial;
  final commands = ReceivePort();
  NativeEmbeddingGemma? native;
  try {
    native = NativeEmbeddingGemma(options);
    parent.send(commands.sendPort);
    await for (final dynamic message in commands) {
      final (id, input) = message as (int, Object?);
      TextEmbeddingResult? result;
      EmbeddingGemmaException? failure;
      try {
        if (input == null) {
          native.close();
        } else {
          final (text, context) = input as (String, TextFormatContext?);
          result = native.embed(text, context);
        }
      } catch (error) {
        failure = _exception(error);
      }
      parent.send((id, result, failure));
      if (input == null) break;
    }
  } catch (error) {
    parent.send(_exception(error));
  } finally {
    try {
      native?.close();
    } finally {
      commands.close();
    }
  }
}

EmbeddingGemmaException _exception(Object error) =>
    error is EmbeddingGemmaException
    ? error
    : EmbeddingGemmaException(error.toString());
