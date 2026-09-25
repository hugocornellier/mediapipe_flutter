import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_text/text_task_backend.dart';

const _channel = MethodChannel('mediapipe_flutter_text/android');

/// Automatically registers Google's Android text SDK with Flutter.
abstract final class MediaPipeTextAndroid {
  /// Installs the backend before the first text task is created.
  static void registerWith() {
    textTaskBackendFactory = _AndroidTextTask.create;
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
    (await _channel.invokeMethod<int>('create', {...options, 'task': task}))!,
  );

  @override
  Future<Map<String, dynamic>> run(String text) async => Map.from(
    (await _channel.invokeMapMethod<String, Object?>('run', {
      'id': _id,
      'text': text,
    }))!,
  );

  @override
  Future<void> dispose() => _channel.invokeMethod<void>('close', {'id': _id});
}
