/// Flutter's registration of Google's Android SDK behind the Audio
/// Classifier. Not for applications: import `mediapipe_audio.dart`.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:mediapipe_audio/platform_interface.dart';
import 'package:mediapipe_core/mediapipe_core.dart';

const _channel = MethodChannel('mediapipe_audio/android');

/// Automatically registers Google's Android audio SDK with Flutter.
abstract final class MediaPipeAudioAndroid {
  /// Installs the backends before the first Audio Classifier is created.
  static void registerWith() {
    audioTaskBackendFactory = _AndroidAudioTask.create;
    audioStreamBackendFactory = _AndroidAudioStream.create;
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

/// Google's Audio Classifier in stream mode, owned by the plugin's worker
/// thread. The plugin runs every call in order on that thread, and its
/// result listener sends each window back as an `update` tagged with the
/// request this side chose when it created the task.
final class _AndroidAudioStream implements AudioStreamBackend {
  _AndroidAudioStream._(this._id, this._request, this._results);

  final int _id;
  final int _request;
  final StreamController<Map<String, Object?>> _results;

  /// Streams waiting for the plugin's updates, by request.
  static final _streams = <int, StreamController<Map<String, Object?>>>{};
  static var _nextRequest = 0;
  static var _listening = false;

  static Future<AudioStreamBackend> create(Map<String, Object?> options) async {
    if (!_listening) {
      // The handler goes in here, with the first stream, not at
      // registration: Flutter registers plugins before its binding exists,
      // and a channel handler set then has no messenger.
      _channel.setMethodCallHandler(_onUpdate);
      _listening = true;
    }
    final request = _nextRequest++;
    final results = _streams[request] =
        StreamController<Map<String, Object?>>();
    try {
      final id = await _call<int>('create', {
        ...options,
        'runningMode': 'AUDIO_STREAM',
        'request': request,
      });
      return _AndroidAudioStream._(id!, request, results);
    } catch (_) {
      _streams.remove(request);
      rethrow;
    }
  }

  /// Routes one `update` from the plugin to its request's stream: an
  /// `error` is Google's failure, a `result` one window's.
  static Future<Object?> _onUpdate(MethodCall call) async {
    if (call.method != 'update') {
      throw MissingPluginException('${call.method} is not implemented.');
    }
    final event = Map<String, Object?>.from(call.arguments as Map);
    final stream = _streams[(event['request']! as num).toInt()];
    if (stream == null) return null;
    if (event['error'] case final String message) {
      stream.addError(TaskException(message));
    } else {
      stream.add(Map<String, Object?>.from(event['result']! as Map));
    }
    return null;
  }

  @override
  Stream<Map<String, Object?>> get results => _results.stream;

  /// Sends the block at once: the method channel keeps the calls in order,
  /// and Google's refusal, which Dart's checks make unreachable in normal
  /// use, arrives on [results].
  @override
  void send(
    Float32List samples,
    double sampleRate,
    int channels,
    int timestampMilliseconds,
  ) => unawaited(
    _call<void>('send', {
      'id': _id,
      'samples': samples,
      'sampleRate': sampleRate,
      'channels': channels,
      'timestampMs': timestampMilliseconds,
    }).catchError((Object error) {
      if (!_results.isClosed) _results.addError(error);
    }),
  );

  /// Google's close flushes the tail. Its listener's `update` is posted to
  /// the platform thread before the reply to the close, so the tail reaches
  /// [results] first; a failure the close reports goes there too.
  @override
  Future<void> dispose() async {
    try {
      await _call<void>('close', {'id': _id});
    } catch (error) {
      _results.addError(error);
    } finally {
      _streams.remove(_request);
      await _results.close();
    }
  }
}
