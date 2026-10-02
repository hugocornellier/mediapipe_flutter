/// Where Audio Classifier runs: a registered platform SDK adapter (Google's
/// browser runtime or Android SDK), or Google's native runtime.
library;

import 'dart:typed_data';

import 'package:mediapipe_core/mediapipe_core.dart';

import 'audio_task_backend.dart';
import 'decoders.dart';
import 'types.dart';

/// Audio Classifier's requests on whichever runtime serves it.
abstract interface class AudioClassifierRunner {
  /// Classifies [audio] after every request submitted before it.
  Future<List<AudioClassifierResult>> classify(AudioData audio);

  /// Waits for accepted requests, then closes Google's task once.
  Future<void> dispose();
}

/// Google's failure as the one exception every task reports.
TaskException taskException(Object error) =>
    error is TaskException ? error : TaskException('$error', cause: error);

/// Audio Classifier on a platform plugin's backend: requests run in
/// submission order and disposal waits for them.
final class BackendAudioClassifier implements AudioClassifierRunner {
  BackendAudioClassifier._(this._task);

  final AudioTaskBackend _task;
  Future<void> _tail = Future.value();
  Future<void>? _disposing;

  /// Starts Google's task through [factory] with [options]' model and
  /// settings, named as in Google's JavaScript API.
  static Future<BackendAudioClassifier> open(
    Future<AudioTaskBackend> Function(Map<String, Object?>) factory,
    AudioClassifierOptions options,
  ) async {
    try {
      return BackendAudioClassifier._(
        await factory({
          'modelBytes': options.modelBytes,
          'modelPath': options.modelPath,
          'delegate': options.delegate.name.toUpperCase(),
          'displayNamesLocale': ?options.displayNamesLocale,
          // -1 (every category) is the JavaScript default; Google's Android
          // SDK rejects any count that is not positive, so it travels unset.
          if (options.maxResults > 0) 'maxResults': options.maxResults,
          'scoreThreshold': options.scoreThreshold,
          if (options.categoryAllowlist.isNotEmpty)
            'categoryAllowlist': options.categoryAllowlist,
          if (options.categoryDenylist.isNotEmpty)
            'categoryDenylist': options.categoryDenylist,
        }),
      );
    } catch (error) {
      throw taskException(error);
    }
  }

  /// Google's browser and mobile tasks read one channel, so several
  /// channels are averaged first.
  @override
  Future<List<AudioClassifierResult>> classify(AudioData audio) {
    if (_disposing != null) {
      return Future.error(StateError('AudioClassifier has been disposed.'));
    }
    final samples = _mono(audio);
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

Float32List _mono(AudioData audio) {
  if (audio.channels == 1) return Float32List.fromList(audio.samples);
  final frames = audio.samples.length ~/ audio.channels;
  final mono = Float32List(frames);
  for (var frame = 0; frame < frames; frame++) {
    var sum = 0.0;
    for (var channel = 0; channel < audio.channels; channel++) {
      sum += audio.samples[frame * audio.channels + channel];
    }
    mono[frame] = sum / audio.channels;
  }
  return mono;
}
