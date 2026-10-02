/// Flutter's registration of Google's Android SDK behind the Audio
/// Classifier. Not for applications: import `mediapipe_audio.dart`.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:mediapipe_audio/platform_interface.dart';
import 'package:mediapipe_core/mediapipe_core.dart';

const _channel = MethodChannel('mediapipe_audio/android');

/// Automatically registers Google's Android audio SDK with Flutter.
abstract final class MediaPipeAudioAndroid {
  /// Installs the backend before the first Audio Classifier is created.
  static void registerWith() {
    audioTaskBackendFactory = _AndroidAudioTask.create;
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

/// Google's Audio Classifier, owned by the plugin's worker thread.
final class _AndroidAudioTask implements AudioTaskBackend {
  _AndroidAudioTask._(this._id);

  final int _id;

  static Future<AudioTaskBackend> create(Map<String, Object?> options) async =>
      _AndroidAudioTask._((await _call<int>('create', options))!);

  @override
  Future<List<Object?>> classify(
    Float32List samples,
    double sampleRate,
  ) async => (await _call<List<Object?>>('run', {
    'id': _id,
    'samples': samples,
    'sampleRate': sampleRate,
  }))!;

  @override
  Future<void> dispose() => _call<void>('close', {'id': _id});
}
