/// Flutter's registration of Google's Android SDK behind the text tasks.
/// Not for applications: import `mediapipe_text.dart`.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_text/platform_interface.dart';

const _channel = MethodChannel('mediapipe_text/android');

/// Automatically registers Google's Android text SDK with Flutter.
abstract final class MediaPipeTextAndroid {
  /// Installs the backend before the first text task is created.
  static void registerWith() {
    textTaskBackendFactory = _AndroidTextTask.create;
  }
}

/// Calls the plugin, reporting its failures as Google's.
Future<T?> _call<T>(String method, Map<String, Object?> arguments) async {
  try {
    return await _channel.invokeMethod<T>(method, arguments);
  } on PlatformException catch (cause) {
    throw TaskException(cause.message ?? cause.code, cause: cause);
  }
}

/// One of Google's text tasks, owned by the plugin's worker thread.
final class _AndroidTextTask implements TextTaskBackend {
  _AndroidTextTask._(this._id);

  final int _id;

  /// Streams waiting for the plugin's updates, by request.
  static final _streams = <int, StreamController<Map<String, dynamic>>>{};
  static var _nextRequest = 0;
  static var _listening = false;

  static Future<TextTaskBackend> create(
    String task,
    Map<String, Object?> options,
  ) async {
    if (!_listening) {
      // The plugin sends the generative tasks' streamed updates back over
      // the same channel, each tagged with its request. The handler goes in
      // here, with the first task, not at registration: Flutter registers
      // plugins before its binding exists, and a channel handler set then
      // has no messenger.
      _channel.setMethodCallHandler(_AndroidTextTask._onUpdate);
      _listening = true;
    }
    return _AndroidTextTask._(
      (await _call<int>('create', {...options, 'task': task}))!,
    );
  }

  /// Routes one `update` from the plugin to its request's stream: an
  /// `error` ends the stream with Google's failure, a `result` is delivered,
  /// and one with `done` ends the stream.
  static Future<Object?> _onUpdate(MethodCall call) async {
    if (call.method != 'update') {
      throw MissingPluginException('${call.method} is not implemented.');
    }
    final event = Map<String, dynamic>.from(call.arguments as Map);
    final request = (event['request'] as num).toInt();
    final stream = _streams[request];
    if (stream == null) return null;
    if (event['error'] case final String message) {
      _streams.remove(request);
      stream.addError(TaskException(message));
      unawaited(stream.close());
      return null;
    }
    final result = Map<String, dynamic>.from(event['result'] as Map);
    stream.add(result);
    if (result['done'] == true) {
      _streams.remove(request);
      unawaited(stream.close());
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> run(
    String text, [
    Map<String, Object?> arguments = const {},
  ]) async => Map.from(
    (await _call<Map<Object?, Object?>>('run', {
      'id': _id,
      'text': text,
      ...arguments,
    }))!,
  );

  @override
  Stream<Map<String, dynamic>> stream(String text) {
    final request = _nextRequest++;
    late final StreamController<Map<String, dynamic>> controller;
    controller = StreamController<Map<String, dynamic>>(
      onListen: () async {
        _streams[request] = controller;
        try {
          await _call<void>('stream', {
            'id': _id,
            'request': request,
            'text': text,
          });
        } catch (error, stack) {
          if (_streams.remove(request) != null) {
            controller.addError(error, stack);
            unawaited(controller.close());
          }
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> dispose() => _call<void>('close', {'id': _id});
}
