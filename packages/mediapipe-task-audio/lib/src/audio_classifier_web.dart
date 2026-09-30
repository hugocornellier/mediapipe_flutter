import 'audio_classifier_backend.dart';
import 'audio_types.dart';

/// Google's official Audio Classifier (for example YAMNet) on audio clips,
/// run in a browser by Google's @mediapipe/tasks-audio on a worker that
/// mediapipe_audio installs.
///
/// Await [dispose] when finished.
///
/// ```dart
/// final task = await AudioClassifier.create(
///   AudioClassifierOptions(model: AudioModels.yamnet),
/// );
/// final result = await task.classify(audio);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class AudioClassifier {
  AudioClassifier._(this._backend);

  final BackendAudioClassifier _backend;

  /// Starts Google's browser task; needs mediapipe_audio.
  static Future<AudioClassifier> create(AudioClassifierOptions options) async =>
      AudioClassifier._(
        await BackendAudioClassifier.create(await options.resolveModel()),
      );

  /// Classifies [audio], one result per chunk the model reads (0.975 s for
  /// YAMNet), in order. Several channels are averaged first.
  Future<List<AudioClassifierResult>> classify(AudioData audio) =>
      _backend.classify(audio);

  /// Waits for queued classifications, then closes Google's task.
  Future<void> dispose() => _backend.dispose();
}
