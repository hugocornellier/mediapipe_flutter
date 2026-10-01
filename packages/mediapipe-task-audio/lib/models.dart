import 'package:mediapipe_core/model_store.dart';

/// Verified official models accepted by audio task options.
abstract final class AudioModels {
  /// Google's YAMNet audio classifier.
  static const yamnet = yamnetModel;

  /// Every model above by the name an app lists to bundle it, under
  /// `hooks.user_defines.mediapipe_audio.models` in pubspec.yaml.
  static const byName = <String, DownloadAsset>{'yamnet': yamnet};
}

/// Google's YAMNet audio classifier, version 1, as MediaPipe Studio uses it.
const yamnetUrl =
    'https://storage.googleapis.com/mediapipe-models/'
    'audio_classifier/yamnet/float32/1/yamnet.tflite';

/// SHA-256 of [yamnetUrl].
const yamnetSha256 =
    '4d8b4a53282dc83ef04e3e7dbc4fbc98082e34e44ed798e16c3a0cdd4c584faf';

/// Google's pinned YAMNet model for the shared model store.
const yamnetModel = DownloadAsset(url: yamnetUrl, sha256: yamnetSha256);
