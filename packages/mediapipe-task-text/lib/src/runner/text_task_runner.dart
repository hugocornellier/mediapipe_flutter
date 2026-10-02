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
/// in Google's JavaScript API and [decode] reading its results, or else on
/// Google's native runtime through [native].
Future<TextTaskRunner<I, R>> openClassicTextTask<I, R, O extends TaskOptions>(
  O options, {
  required Future<TaskCapabilities> Function() capabilities,
  required String task,
  required Map<String, Object?> settings,
  required R Function(Map<String, dynamic> json) decode,
  required String Function(I input) text,
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
    return _BackendInput(backend, text);
  }
  return native(options);
}

/// Classifier settings named as in Google's JavaScript API.
///
/// The threshold is always sent, as Google's Python and C APIs apply it:
/// left unset, its JavaScript and mobile SDKs apply the model's own
/// threshold (the language detector's drops all but the top language), so
/// the same options would answer differently from the native runtime. A
/// negative count means every category, which Google's Android SDK only
/// accepts as an unset option.
Map<String, Object?> classifierSettings({
  required String? displayNamesLocale,
  required int maxResults,
  required double scoreThreshold,
  required List<String> categoryAllowlist,
  required List<String> categoryDenylist,
}) => {
  'displayNamesLocale': ?displayNamesLocale,
  if (maxResults > 0) 'maxResults': maxResults,
  'scoreThreshold': scoreThreshold,
  if (categoryAllowlist.isNotEmpty) 'categoryAllowlist': categoryAllowlist,
  if (categoryDenylist.isNotEmpty) 'categoryDenylist': categoryDenylist,
};

/// One of Google's text tasks on a platform plugin's backend: requests run
/// in submission order and disposal waits for them.
final class BackendTextTask<R> implements TextTaskRunner<String, R> {
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

/// Adapts a backend that takes plain text to a task whose requests carry
/// more, such as the embedder's format context, which [_text] reads or
/// refuses.
final class _BackendInput<I, R> implements TextTaskRunner<I, R> {
  _BackendInput(this._backend, this._text);
  final BackendTextTask<R> _backend;
  final String Function(I input) _text;

  @override
  Future<R> run(I input) async => _backend.run(_text(input));

  @override
  Future<void> dispose() => _backend.dispose();
}
