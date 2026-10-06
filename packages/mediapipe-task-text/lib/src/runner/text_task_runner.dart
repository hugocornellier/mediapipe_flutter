/// Where one text task runs: a registered platform SDK adapter (Google's
/// browser runtime or Android SDK), or Google's native runtime on a worker
/// isolate. Every task class forwards here, on every platform.
library;

import 'dart:async';

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import '../text_task_backend.dart';
import '../types/format_context.dart';

/// A Text Embedder request: the text and its optional format context.
typedef TextEmbedderInput = (String, TextFormatContext?);

/// A request as a platform backend takes it: the text and the arguments
/// Google's runtime takes with it, named as in its JavaScript API.
typedef BackendRequest = (String text, Map<String, Object?> arguments);

/// One task's requests, on whichever runtime serves it. [I] is the request:
/// the text, or the text and its format context.
abstract interface class TextTaskRunner<I, R> {
  /// Runs [input] after every request submitted before it.
  Future<R> run(I input);

  /// Waits for accepted requests, then closes Google's task once.
  Future<void> dispose();
}

/// A runner that can also stream a request's partial results.
abstract interface class TextStreamRunner<I, R, U>
    implements TextTaskRunner<I, R> {
  /// Starts on listen; cancelling stops delivery, not Google's generation.
  Stream<U> stream(I input);
}

/// Google's failure as the one exception every task reports.
TaskException taskException(Object error) =>
    error is TaskException ? error : TaskException('$error');

/// The checks every text request gets on every platform before it reaches
/// Google's runtime, so the same call fails the same way everywhere.
final class TextTaskSession<I, R> {
  /// Wraps [runner]; [name] appears in errors.
  TextTaskSession(this.name, this.runner);

  /// The task's name, as its errors say it.
  final String name;

  /// The runtime serving the task.
  final TextTaskRunner<I, R> runner;

  Future<void>? _disposing;

  /// Rejects a request after disposal or with text Google's C API would
  /// truncate.
  void check(String text) {
    if (_disposing != null) throw StateError('$name has been disposed.');
    if (text.contains('\u0000')) {
      throw ArgumentError.value(text, 'text', 'Must not contain NUL.');
    }
  }

  /// Checks [text], then runs [input]; errors arrive through the Future.
  Future<R> run(String text, I input) async {
    check(text);
    return runner.run(input);
  }

  /// Waits for accepted requests and closes the task; repeated calls return
  /// the same completion.
  Future<void> dispose() => _disposing ??= runner.dispose();
}

/// Opens a classic text task (Text Classifier, Text Embedder or Language
/// Detector) after [capabilities] admits the delegate: through the
/// registered platform backend as Google's [task], with [settings] named as
/// in Google's JavaScript API, [request] turning each input into the text
/// and its per-call arguments, and [decode] reading its results, or else on
/// Google's native runtime through [native].
Future<TextTaskRunner<I, R>> openClassicTextTask<I, R, O extends TaskOptions>(
  O options, {
  required Future<TaskCapabilities> Function() capabilities,
  required String task,
  required Map<String, Object?> settings,
  required R Function(Map<String, dynamic> json) decode,
  required BackendRequest Function(I input) request,
  required Future<TextTaskRunner<I, R>> Function(O options) native,
}) async {
  requireDelegate(await capabilities(), options.delegate);
  await resolveTaskModel(options);
  if (textTaskBackendFactory case final factory?) {
    final backend = await BackendTextTask.open(factory, task, {
      'modelBytes': options.modelBytes,
      'modelPath': options.modelPath,
      'delegate': options.delegate.name.toUpperCase(),
      ...settings,
    }, decode);
    return _BackendInput(backend, request);
  }
  return native(options);
}

/// Opens a generative text task (Proofreader or Summarizer) after
/// [capabilities] admits the delegate: through the registered platform
/// backend (Google's Android SDK) as Google's [task] with [settings], or
/// else on Google's native runtime through [native].
///
/// Google's Android options take no cache directory, so a [cacheDirectory]
/// fails there with that reason rather than being ignored.
Future<TextStreamRunner<String, R, U>>
openGenerativeTextTask<R, U, O extends TaskOptions>(
  O options, {
  required Future<TaskCapabilities> Function() capabilities,
  required String task,
  required Map<String, Object?> settings,
  required String? cacheDirectory,
  required R Function(Map<String, dynamic> json) decodeResult,
  required U Function(Map<String, dynamic> json) decodeUpdate,
  required Future<TextStreamRunner<String, R, U>> Function(O options) native,
}) async {
  requireDelegate(await capabilities(), options.delegate);
  await resolveTaskModel(options);
  if (textTaskBackendFactory case final factory?) {
    if (cacheDirectory != null) {
      throw const RuntimeUnavailableException(
        "Google's Android SDK takes no cache directory for this task.",
        fix:
            'Omit cacheDirectory on Android; the Proofreader and Summarizer '
            "options of Google's Android SDK have no such setting.",
      );
    }
    return BackendStreamTextTask.open(
      factory,
      task,
      {'modelPath': options.modelPath, ...settings},
      decodeResult,
      decodeUpdate,
    );
  }
  return native(options);
}

/// A format context named as Google's JavaScript `TextFormatOptions`, which
/// its Android SDK's `TextFormatContext` reads by the same names.
Map<String, Object?> formatContextSettings(TextFormatContext context) => {
  'type': _embeddingTypes[context.taskType]!,
  'title': ?context.title,
  'textRole': context.role == TextRole.document ? 'DOCUMENT' : 'QUERY',
};

const _embeddingTypes = {
  EmbeddingType.retrievalQuery: 'RETRIEVAL_QUERY',
  EmbeddingType.retrievalDocument: 'RETRIEVAL_DOCUMENT',
  EmbeddingType.semanticSimilarity: 'SEMANTIC_SIMILARITY',
  EmbeddingType.classification: 'CLASSIFICATION',
  EmbeddingType.clustering: 'CLUSTERING',
  EmbeddingType.questionAnswering: 'QUESTION_ANSWERING',
  EmbeddingType.factChecking: 'FACT_CHECKING',
  EmbeddingType.codeRetrieval: 'CODE_RETRIEVAL',
};

/// One of Google's text tasks on a platform plugin's backend: requests run
/// in submission order and disposal waits for them.
final class BackendTextTask<R> implements TextTaskRunner<BackendRequest, R> {
  BackendTextTask._(this._backend, this._decode);

  /// Creates Google's [task] with [options] through [factory].
  static Future<BackendTextTask<R>> open<R>(
    Future<TextTaskBackend> Function(String, Map<String, Object?>) factory,
    String task,
    Map<String, Object?> options,
    R Function(Map<String, dynamic> json) decode,
  ) async {
    try {
      return BackendTextTask._(await factory(task, options), decode);
    } catch (error) {
      throw taskException(error);
    }
  }

  final TextTaskBackend _backend;
  final R Function(Map<String, dynamic> json) _decode;
  Future<void> _tail = Future.value();
  Future<void>? _disposing;

  @override
  Future<R> run(BackendRequest request) {
    if (_disposing != null) {
      return Future.error(StateError('Text task has been disposed.'));
    }
    final result = _tail.then((_) async {
      final Map<String, dynamic> json;
      try {
        json = await _backend.run(request.$1, request.$2);
      } catch (error) {
        throw taskException(error);
      }
      return _decode(json);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> dispose() => _disposing ??= _tail.then((_) async {
    try {
      await _backend.dispose();
    } catch (error) {
      throw taskException(error);
    }
  });
}

/// Adapts a backend to a task whose requests carry more than text, such as
/// the embedder's format context, which [_request] turns into the backend's
/// arguments.
final class _BackendInput<I, R> implements TextTaskRunner<I, R> {
  _BackendInput(this._backend, this._request);
  final BackendTextTask<R> _backend;
  final BackendRequest Function(I input) _request;

  @override
  Future<R> run(I input) async => _backend.run(_request(input));

  @override
  Future<void> dispose() => _backend.dispose();
}

/// One of Google's generative text tasks on a platform plugin's backend, with
/// the stream behavior of the native worker: completed and streamed requests
/// run in submission order, a stream starts on listen and has one
/// subscription, pausing buffers its updates, cancelling stops delivery and
/// waits for Google's generation to finish, and disposal waits for every
/// accepted request.
final class BackendStreamTextTask<R, U>
    implements TextStreamRunner<String, R, U> {
  BackendStreamTextTask._(
    this._backend,
    this._decodeResult,
    this._decodeUpdate,
  );

  /// Creates Google's [task] with [options] through [factory].
  static Future<BackendStreamTextTask<R, U>> open<R, U>(
    Future<TextTaskBackend> Function(String, Map<String, Object?>) factory,
    String task,
    Map<String, Object?> options,
    R Function(Map<String, dynamic> json) decodeResult,
    U Function(Map<String, dynamic> json) decodeUpdate,
  ) async {
    try {
      return BackendStreamTextTask._(
        await factory(task, options),
        decodeResult,
        decodeUpdate,
      );
    } catch (error) {
      throw taskException(error);
    }
  }

  final TextTaskBackend _backend;
  final R Function(Map<String, dynamic> json) _decodeResult;
  final U Function(Map<String, dynamic> json) _decodeUpdate;
  Future<void> _tail = Future.value();
  Future<void>? _disposing;

  @override
  Future<R> run(String text) {
    if (_disposing != null) {
      return Future.error(StateError('Text task has been disposed.'));
    }
    final result = _tail.then((_) async {
      final Map<String, dynamic> json;
      try {
        json = await _backend.run(text);
      } catch (error) {
        throw taskException(error);
      }
      return _decodeResult(json);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Stream<U> stream(String text) {
    late final StreamController<U> controller;
    Future<void>? finished;
    var cancelled = false;
    controller = StreamController<U>(
      onListen: () {
        if (_disposing != null) {
          controller.addError(StateError('Text task has been disposed.'));
          unawaited(controller.close());
          return;
        }
        final operation = _tail.then((_) async {
          try {
            await for (final json in _backend.stream(text)) {
              if (!cancelled) controller.add(_decodeUpdate(json));
            }
          } catch (error, stack) {
            if (!cancelled) controller.addError(taskException(error), stack);
          }
          unawaited(controller.close());
        });
        finished = operation;
        _tail = operation.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
      },
      onCancel: () async {
        cancelled = true;
        await finished;
      },
    );
    return controller.stream;
  }

  @override
  Future<void> dispose() => _disposing ??= _tail.then((_) async {
    try {
      await _backend.dispose();
    } catch (error) {
      throw taskException(error);
    }
  });
}
