/// The browser plumbing the text and audio plugins share: one worker per
/// task, created from the family's worker script, with requests and
/// disposal in order. Web only, and not for applications.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'src/exceptions.dart';
import 'src/web_runtime.dart';

@JS('mediapipeTasks.create')
external JSPromise<JSNumber> _create(JSString workerUrl, JSObject options);
@JS('mediapipeTasks.run')
external JSPromise<JSString> _run(JSNumber id, JSObject input);
@JS('mediapipeTasks.close')
external JSPromise<JSAny?> _close(JSNumber id);

/// One of Google's tasks on its own worker, from the family's
/// `assets/worker.js`.
final class WebTaskWorker {
  WebTaskWorker._(this._id);
  final JSNumber _id;
  static Future<void>? _loaded;

  /// Starts a worker from [family]'s worker script (`mediapipe_text` or
  /// `mediapipe_audio`) and creates its task from [options]: the task's
  /// settings named as in Google's JavaScript API, plus `modelBytes` or
  /// `modelPath`, a URL resolved against the page.
  static Future<WebTaskWorker> create(
    String family,
    Map<String, Object?> options,
  ) async {
    await (_loaded ??= _loadBridge());
    final bytes = options['modelBytes'] as Uint8List?;
    final path = options['modelPath'] as String?;
    final input = {
      ...options,
      'modelBytes': bytes == null ? null : Uint8List.fromList(bytes).toJS,
      'modelPath': path == null ? null : Uri.base.resolve(path).toString(),
      'runtimeBaseUrl': MediaPipeWebRuntime.resolve(Uri.base),
    }.jsify()!;
    final worker = Uri.base.resolve('assets/packages/$family/assets/worker.js');
    return WebTaskWorker._(
      await _reported(_create(worker.toString().toJS, input as JSObject)),
    );
  }

  /// Runs one request after every request submitted before it and returns
  /// the worker's JSON.
  Future<String> run(JSObject input) async =>
      (await _reported(_run(_id, input))).toDart;

  /// Waits for queued requests, then closes the task and its worker.
  Future<void> close() => _reported(_close(_id));
}

/// Google's failure, from the worker, as the one task exception.
Future<T> _reported<T extends JSAny?>(JSPromise<T> promise) async {
  try {
    return await promise.toDart;
  } catch (error) {
    throw TaskException('$error', cause: error);
  }
}

/// Adds core's bridge script to the page once; a failure can be retried.
Future<void> _loadBridge() async {
  final script = web.HTMLScriptElement()
    ..src = Uri.base
        .resolve('assets/packages/mediapipe_core/assets/task_bridge.js')
        .toString();
  final ready = Completer<void>();
  unawaited(script.onLoad.first.then((_) => ready.complete()));
  unawaited(
    script.onError.first.then((_) {
      ready.completeError(
        StateError('Unable to load the MediaPipe web bridge.'),
      );
    }),
  );
  web.document.head!.append(script);
  try {
    await ready.future.timeout(const Duration(seconds: 60));
  } catch (_) {
    script.remove();
    WebTaskWorker._loaded = null;
    rethrow;
  }
}
