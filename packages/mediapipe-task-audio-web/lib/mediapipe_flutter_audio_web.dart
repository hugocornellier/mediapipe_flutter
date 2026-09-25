import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:mediapipe_flutter_audio/audio_task_backend.dart';
import 'package:web/web.dart' as web;

@JS('mediapipeAudio.create')
external JSPromise<JSNumber> _create(JSObject options);
@JS('mediapipeAudio.run')
external JSPromise<JSString> _run(JSNumber id, JSObject input);
@JS('mediapipeAudio.close')
external JSPromise<JSAny?> _close(JSNumber id);

/// Flutter registration for Google's official browser audio runtime.
abstract final class MediaPipeAudioWeb {
  /// Installs the browser backend before the first Audio Classifier.
  static void registerWith(Registrar registrar) {
    audioTaskBackendFactory = _WorkerAudioTask.create;
  }
}

/// Google's Audio Classifier on its own worker (assets/worker.js).
final class _WorkerAudioTask implements AudioTaskBackend {
  _WorkerAudioTask._(this._id);

  final JSNumber _id;
  static Future<void>? _loaded;

  static Future<AudioTaskBackend> create(Map<String, Object?> options) async {
    await (_loaded ??= _loadBridge(
      'assets/packages/mediapipe_flutter_audio_web/assets/bridge.js',
      () => _loaded = null,
    ));
    final bytes = options['modelBytes'] as Uint8List?;
    final path = options['modelPath'] as String?;
    final input = {
      ...options,
      'modelBytes': bytes == null ? null : Uint8List.fromList(bytes).toJS,
      // A model path is a URL here, resolved against the page.
      'modelPath': path == null ? null : Uri.base.resolve(path).toString(),
    }.jsify()!;
    return _WorkerAudioTask._(await _create(input as JSObject).toDart);
  }

  @override
  Future<List<Object?>> classify(Float32List samples, double sampleRate) async {
    final input = JSObject()
      ..['samples'] = Float32List.fromList(samples).toJS
      ..['sampleRate'] = sampleRate.toJS;
    final json = await _run(_id, input).toDart;
    return jsonDecode(json.toDart) as List<Object?>;
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
