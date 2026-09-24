import 'dart:typed_data';

import '../audio_task_backend.dart';
import 'audio_types.dart';

/// Audio Classifier on a platform plugin's backend (audio_task_backend.dart):
/// Google's browser runtime, or its Android or iOS SDK.
final class BackendAudioClassifier {
  BackendAudioClassifier._(this._task);

  final AudioTaskBackend _task;
  Future<void>? _disposing;
  Future<void> _tail = Future.value();

  /// Starts Google's task on the registered backend.
  static Future<BackendAudioClassifier> create(
    AudioClassifierOptions options,
  ) async {
    final factory = audioTaskBackendFactory;
    if (factory == null) {
      throw UnsupportedError(
        'Audio Classifier here runs through a platform plugin that is '
        'missing: add mediapipe_flutter_audio_web for browsers, or '
        'mediapipe_flutter_audio_android or mediapipe_flutter_audio_ios for '
        'mobile.',
      );
    }
    try {
      return BackendAudioClassifier._(
        await factory({
          'modelBytes': options.modelBytes,
          'modelPath': options.modelPath,
          'maxResults': options.maxResults,
          'scoreThreshold': options.scoreThreshold,
        }),
      );
    } catch (error) {
      throw AudioClassifierException('$error');
    }
  }

  /// Classifies [audio], one result per chunk the model reads (0.975 s for
  /// YAMNet), in order. Google's browser and mobile tasks read one channel,
  /// so several channels are averaged first.
  Future<List<AudioClassification>> classify(AudioData audio) {
    if (_disposing != null) {
      return Future.error(StateError('AudioClassifier has been disposed.'));
    }
    final samples = _mono(audio);
    final result = _tail.then((_) async {
      try {
        return [
          for (final chunk in await _task.classify(samples, audio.sampleRate))
            _chunk(chunk! as Map),
        ];
      } catch (error) {
        throw AudioClassifierException('$error');
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Waits for queued classifications, then closes Google's task.
  Future<void> dispose() => _disposing ??= _tail.then((_) => _task.dispose());
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

AudioClassification _chunk(Map chunk) {
  final heads = chunk['classifications'] as List? ?? const [];
  return (
    timestampMs: (chunk['timestampMs'] as num?)?.toInt() ?? 0,
    categories: [
      if (heads.isNotEmpty)
        for (final category in (heads.first as Map)['categories'] as List)
          (
            index: ((category as Map)['index'] as num).toInt(),
            score: (category['score'] as num).toDouble(),
            name: switch (category['categoryName']) {
              final String name when name.isNotEmpty => name,
              _ => null,
            },
          ),
    ],
  );
}
