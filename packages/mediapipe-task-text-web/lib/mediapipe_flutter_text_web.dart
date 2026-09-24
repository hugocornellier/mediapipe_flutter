import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:mediapipe_flutter_text/text_task_backend.dart';
import 'package:web/web.dart' as web;

@JS('mediapipeText.create')
external JSPromise<JSNumber> _create(JSObject options);
@JS('mediapipeText.run')
external JSPromise<JSString> _run(JSNumber id, JSObject input);
@JS('mediapipeText.close')
external JSPromise<JSAny?> _close(JSNumber id);

/// Flutter registration for Google's official browser text runtime.
abstract final class MediaPipeTextWeb {
  /// Installs the browser backend before the first text task is created.
  static void registerWith(Registrar registrar) {
    textTaskBackendFactory = _WorkerTextTask.create;
  }
}

/// One of Google's text tasks on its own worker (assets/worker.js).
final class _WorkerTextTask implements TextTaskBackend {
  _WorkerTextTask._(this._id);

  final JSNumber _id;
  static Future<void>? _loaded;

  static Future<TextTaskBackend> create(
    String task,
    Map<String, Object?> options,
  ) async {
    await (_loaded ??= _loadBridge(
      'assets/packages/mediapipe_flutter_text_web/assets/bridge.js',
      () => _loaded = null,
    ));
    final bytes = options['modelBytes'] as Uint8List?;
    final input = {
      ...options,
      'task': task,
      'modelBytes': bytes == null ? null : Uint8List.fromList(bytes).toJS,
    }.jsify()!;
    return _WorkerTextTask._(await _create(input as JSObject).toDart);
  }

  @override
  Future<Map<String, dynamic>> run(String text) async {
    final json = await _run(_id, {'text': text}.jsify()! as JSObject).toDart;
    return jsonDecode(json.toDart) as Map<String, dynamic>;
  }

  @override
  Future<void> dispose() => _close(_id).toDart;
}

/// Adds the bridge script to the page once; a failure can be retried.
Future<void> _loadBridge(String path, void Function() reset) async {
  final script = web.HTMLScriptElement()
    ..src = Uri.base.resolve(path).toString();
  final ready = Completer<void>();
  script.onLoad.first.then((_) => ready.complete());
  script.onError.first.then((_) {
    ready.completeError(StateError('Unable to load the MediaPipe web bridge.'));
  });
  web.document.head!.append(script);
  try {
    await ready.future.timeout(const Duration(seconds: 60));
  } catch (_) {
    script.remove();
    reset();
    rethrow;
  }
}
