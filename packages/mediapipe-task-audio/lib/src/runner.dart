/// Where Audio Classifier runs: a registered platform SDK adapter (Google's
/// browser runtime or Android SDK), or Google's native runtime.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart'
    show classifierSettingsJson;

import 'audio_task_backend.dart';
import 'decoders.dart';
import 'stream/emulation.dart';
import 'stream/results.dart';
import 'types.dart';

/// Audio Classifier's requests on whichever runtime serves it.
abstract interface class AudioClassifierRunner {
  /// Classifies [audio] after every request submitted before it.
  Future<List<AudioClassifierResult>> classify(AudioData audio);

  /// Waits for accepted requests, then closes Google's task once.
  Future<void> dispose();
}

/// An Audio Classifier stream on whichever runtime serves it: Google's own
/// stream on Android, iOS, macOS, Linux and Windows, an emulation on its
/// clips mode in browsers. Results go to the task's [AudioStreamResults].
abstract interface class AudioStreamRunner {
  /// Hands on a block that passed the task's checks and holds samples, after
  /// every block before it.
  void send(AudioData block, int timestampMilliseconds);

  /// Flushes the tail as Google's close does, delivers what that yields,
  /// then releases Google's task. Reports a failure through the results.
  Future<void> close();
}

/// Google's failure as the one exception every task reports.
TaskException taskException(Object error) =>
    error is TaskException ? error : TaskException('$error', cause: error);

/// [options]' model and settings, named as in Google's JavaScript API, with
/// [modelBytes] in place of the options' model when given.
Map<String, Object?> backendSettings(
  AudioClassifierOptions options, {
  Uint8List? modelBytes,
}) => {
  'modelBytes': modelBytes ?? options.modelBytes,
  'modelPath': modelBytes == null ? options.modelPath : null,
  'delegate': options.delegate.name.toUpperCase(),
  ...classifierSettingsJson(options),
};

/// Audio Classifier on a platform plugin's backend: requests run in
/// submission order and disposal waits for them.
final class BackendAudioClassifier implements AudioClassifierRunner {
  BackendAudioClassifier._(this._task);

  final AudioTaskBackend _task;
  Future<void> _tail = Future.value();
  Future<void>? _disposing;

  /// Starts Google's task through [factory] with [options]' model and
  /// settings, named as in Google's JavaScript API; with [modelBytes] in
  /// place of the options' model when given.
  static Future<BackendAudioClassifier> open(
    Future<AudioTaskBackend> Function(Map<String, Object?>) factory,
    AudioClassifierOptions options, {
    Uint8List? modelBytes,
  }) async {
    try {
      return BackendAudioClassifier._(
        await factory(backendSettings(options, modelBytes: modelBytes)),
      );
    } catch (error) {
      throw taskException(error);
    }
  }

  /// Google's browser tasks read one channel, so several channels are
  /// averaged first. Its Android SDK reads them as they are, but the plugin
  /// sends one, the same samples as the browser's.
  @override
  Future<List<AudioClassifierResult>> classify(AudioData audio) {
    if (_disposing != null) {
      return Future.error(StateError('AudioClassifier has been disposed.'));
    }
    final samples = monoSamples(audio.samples, audio.channels);
    final result = _tail.then((_) async {
      final List<Object?> json;
      try {
        json = await _task.classify(samples, audio.sampleRate);
      } catch (error) {
        throw taskException(error);
      }
      return decodeAudioClassifierResults(json);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> dispose() => _disposing ??= _tail.then((_) async {
    try {
      await _task.dispose();
    } catch (error) {
      throw taskException(error);
    }
  });
}

/// The stream in browsers: Google's browser runtime has no stream, so the
/// emulation frames the blocks and classifies each window with the
/// browser's clips mode.
final class EmulatedStreamRunner implements AudioStreamRunner {
  /// Emulates the stream of [results]' model on a clips task, whose
  /// disposal this runner's close ends with.
  EmulatedStreamRunner(this._clips, AudioStreamResults results)
    : _stream = EmulatedAudioStream(
        results.specs,
        (samples, sampleRate, channels) => _clips.classify(
          AudioData(
            samples: samples,
            sampleRate: sampleRate,
            channels: channels,
          ),
        ),
        results,
      );

  final AudioClassifierRunner _clips;
  final EmulatedAudioStream _stream;

  @override
  void send(AudioData block, int timestampMilliseconds) => _stream.add(block);

  @override
  Future<void> close() async {
    try {
      await _stream.close();
    } finally {
      await _clips.dispose();
    }
  }
}

/// Google's own stream through a platform plugin's stream backend: its
/// Android SDK. Google stamps the windows; the results restamp the tail.
final class BackendStreamRunner implements AudioStreamRunner {
  BackendStreamRunner._(this._backend, this._results) {
    _subscription = _backend.results.listen(
      (json) {
        for (final result in decodeAudioClassifierResults([json])) {
          _results.addGoogle(result);
        }
      },
      onError: (Object error, StackTrace stack) =>
          _results.fail(taskException(error), stack),
      onDone: _done.complete,
    );
  }

  final AudioStreamBackend _backend;
  final AudioStreamResults _results;
  late final StreamSubscription<Map<String, Object?>> _subscription;
  final _done = Completer<void>();

  /// Starts Google's stream through [factory] with [options]' model and
  /// settings, delivering to [results].
  static Future<BackendStreamRunner> open(
    Future<AudioStreamBackend> Function(Map<String, Object?>) factory,
    AudioClassifierOptions options,
    AudioStreamResults results,
  ) async {
    try {
      return BackendStreamRunner._(
        await factory(backendSettings(options)),
        results,
      );
    } catch (error) {
      throw taskException(error);
    }
  }

  @override
  void send(AudioData block, int timestampMilliseconds) => _backend.send(
    block.samples,
    block.sampleRate,
    block.channels,
    timestampMilliseconds,
  );

  @override
  Future<void> close() async {
    try {
      // Google's Android runner reports a graph failure only when it closes
      // (upstream-issues.md UP-039); the backend delivers it on its
      // results, before they close.
      await _backend.dispose();
      await _done.future;
    } catch (error, stack) {
      _results.fail(taskException(error), stack);
    } finally {
      await _subscription.cancel();
    }
  }
}
