import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_audio/audio_task_backend.dart';

const _channel = MethodChannel('mediapipe_flutter_audio/android');

/// Automatically registers Google's Android audio SDK with Flutter.
abstract final class MediaPipeAudioAndroid {
  /// Installs the backend before the first Audio Classifier is created.
  static void registerWith() {
    audioTaskBackendFactory = _AndroidAudioTask.create;
  }
}

/// Google's Audio Classifier, owned by the plugin's worker thread.
final class _AndroidAudioTask implements AudioTaskBackend {
  _AndroidAudioTask._(this._id);

  final int _id;

  static Future<AudioTaskBackend> create(Map<String, Object?> options) async =>
      _AndroidAudioTask._(
        (await _channel.invokeMethod<int>('create', options))!,
      );

  @override
  Future<List<Object?>> classify(
    Float32List samples,
    double sampleRate,
  ) async => (await _channel.invokeListMethod<Object?>('run', {
    'id': _id,
    'samples': samples,
    'sampleRate': sampleRate,
  }))!;

  @override
  Future<void> dispose() => _channel.invokeMethod<void>('close', {'id': _id});
}
