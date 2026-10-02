/// Flutter's registration of Google's Android SDK behind the classic text
/// tasks. Not for applications: import `mediapipe_text.dart`.
library;

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

  static Future<TextTaskBackend> create(
    String task,
    Map<String, Object?> options,
  ) async => _AndroidTextTask._(
    (await _call<int>('create', {...options, 'task': task}))!,
  );

  @override
  Future<Map<String, dynamic>> run(String text) async => Map.from(
    (await _call<Map<Object?, Object?>>('run', {'id': _id, 'text': text}))!,
  );

  @override
  Future<void> dispose() => _call<void>('close', {'id': _id});
}
