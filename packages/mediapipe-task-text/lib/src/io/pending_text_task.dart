import 'dart:async';

import '../interface/text_task_exception.dart';
import 'classic_text_runtime.dart';
import 'text_task_worker.dart';

/// Adapts the original synchronous constructors to the shared worker lifecycle.
final class PendingTextTask<R> {
  PendingTextTask._(this._ready) {
    unawaited(_ready.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  /// Start initialization immediately, reporting failure through ready/run.
  static PendingTextTask<R> start<R, O>({
    required String name,
    required O options,
    required NativeTextTask<R, Never> Function(O) create,
  }) {
    requireTextTasksRuntime();
    final worker = TextTaskWorker.start(
      name: name,
      options: options,
      create: create,
      exception: _exception,
    );
    // A constructor cannot return a Future. Keep an early initialization error
    // handled until a caller awaits ready, inference or disposal.
    return PendingTextTask<R>._(worker);
  }

  final Future<TextTaskWorker<R, Never, TextTaskException>> _ready;
  bool _disposing = false;
  Future<void>? _disposeFuture;

  /// Await initialization without exposing the native worker.
  Future<void> get ready async {
    await _ready;
  }

  /// Preserve submission order, including requests queued before ready.
  Future<R> run(String text) async {
    checkActive();
    if (text.contains('\u0000')) {
      throw ArgumentError('Text must not contain NUL.');
    }
    return (await _ready).run(text);
  }

  /// Reject new requests as soon as disposal begins.
  void checkActive() {
    if (_disposing) throw StateError('Text task has been disposed.');
  }

  /// Wait for initialization, queued work, native close and isolate exit.
  Future<void> dispose() {
    _disposing = true;
    return _disposeFuture ??= _close();
  }

  Future<void> _close() async => (await _ready).dispose();
}

TextTaskException _exception(Object error) =>
    error is TextTaskException ? error : TextTaskException(error.toString());
