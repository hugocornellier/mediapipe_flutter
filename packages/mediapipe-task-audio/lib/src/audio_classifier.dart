import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_core/platform_interface.dart';

import 'audio_task_backend.dart';
import 'capabilities.dart';
import 'native_tasks.dart';
import 'runner.dart';
import 'types.dart';

/// Google's Audio Classifier (for example YAMNet): the categories of each
/// chunk of an audio clip.
///
/// One class on every platform. Google's native runtime serves it on macOS,
/// Linux, Windows and iOS, classifying on a background isolate; its Android
/// SDK and browser runtime serve it through the registered platform plugin.
///
/// ```dart
/// final task = await AudioClassifier.create(
///   AudioClassifierOptions(model: AudioModels.yamnet),
/// );
/// final results = await task.classify(audio);
/// await task.dispose();
/// ```
/// Calls run one at a time, in call order. A `Future` cannot cancel native
/// work; `dispose()` waits for work already accepted and is idempotent.
final class AudioClassifier {
  AudioClassifier._(this._runner, this.delegate, this.runningMode);
  final AudioClassifierRunner _runner;
  Future<void>? _disposing;

  /// The processor the task runs on, fixed at creation.
  final Delegate delegate;

  /// The mode the task was created in.
  final AudioRunningMode runningMode;

  /// Resolves the model and opens Google's task.
  static Future<AudioClassifier> create(AudioClassifierOptions options) async {
    // TODO: Remove this rejection when audio stream mode is implemented. See
    // AudioRunningMode.audioStream.
    if (options.runningMode == AudioRunningMode.audioStream) {
      throw UnsupportedError(
        'Audio stream mode is not implemented by this runtime.',
      );
    }
    requireDelegate(await queryAudioClassifierCapabilities(), options.delegate);
    await resolveTaskModel(options);
    final runner = switch (audioTaskBackendFactory) {
      final factory? => await BackendAudioClassifier.open(factory, options),
      null => await openNativeAudioClassifier(options),
    };
    return AudioClassifier._(runner, options.delegate, options.runningMode);
  }

  /// Classifies [audio]: one result per chunk the model reads (0.975 s for
  /// YAMNet), in order. Google's browser and Android tasks read one channel,
  /// so there several channels are averaged first.
  Future<List<AudioClassifierResult>> classify(AudioData audio) async {
    if (_disposing != null) {
      throw StateError('AudioClassifier has been disposed.');
    }
    return _runner.classify(audio);
  }

  /// Finishes accepted work and releases Google's task. Repeated calls return
  /// the same completion; any other call afterwards fails with [StateError].
  Future<void> dispose() => _disposing ??= _runner.dispose();
}
