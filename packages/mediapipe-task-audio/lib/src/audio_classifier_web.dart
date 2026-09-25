import 'audio_classifier_backend.dart';
import 'audio_types.dart';

/// Google's official Audio Classifier (for example YAMNet) on audio clips,
/// run in a browser by Google's @mediapipe/tasks-audio on a worker that
/// mediapipe_flutter_audio_web installs.
///
/// Await [dispose] when finished.
final class AudioClassifier {
  AudioClassifier._(this._backend);

  final BackendAudioClassifier _backend;

  /// Starts Google's browser task; needs mediapipe_flutter_audio_web.
  static Future<AudioClassifier> create(AudioClassifierOptions options) async =>
      AudioClassifier._(await BackendAudioClassifier.create(options));

  /// Classifies [audio], one result per chunk the model reads (0.975 s for
  /// YAMNet), in order. Several channels are averaged first.
  Future<List<AudioClassification>> classify(AudioData audio) =>
      _backend.classify(audio);

  /// Waits for queued classifications, then closes Google's task.
  Future<void> dispose() => _backend.dispose();
}
