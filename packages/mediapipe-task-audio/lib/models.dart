/// The verified official models of the audio tasks, [AudioModels], which
/// `mediapipe_audio.dart` also exports. `bundle_models` reads them from this
/// library alone.
library;

import 'package:mediapipe_core/mediapipe_core.dart';

/// Verified official models accepted by audio task options.
abstract final class AudioModels {
  /// Google's YAMNet audio classifier, version 1, as MediaPipe Studio uses it.
  static const yamnet = DownloadAsset(
    url:
        'https://storage.googleapis.com/mediapipe-models/'
        'audio_classifier/yamnet/float32/1/yamnet.tflite',
    sha256: '4d8b4a53282dc83ef04e3e7dbc4fbc98082e34e44ed798e16c3a0cdd4c584faf',
  );

  /// NVIDIA's Parakeet TDT 0.6B v3 speech recognizer for the Audio
  /// Transcriber, as Google's LiteRT community converted it (int8, 5 s
  /// stateful windows, 25 European languages): 615 MB, CC BY 4.0.
  static const parakeetTdtV3 = DownloadAsset(
    url:
        'https://huggingface.co/litert-community/parakeet-tdt-0.6b-v3/'
        'resolve/1f78e5eb6175b1b2cce35f16bcf9e2027b83e8bd/'
        'parakeet_tdt_0.6b_v3_5s_i8_stateful.litertlm',
    sha256: '66c5a74cf6c2c1d2b990901f6cece5bb53e3214dbceafa0989900a6f0eeb3504',
  );

  /// Google's Phonon 31M voices for Text to Speech (int8; US English,
  /// French, German, Spanish and Brazilian Portuguese at 24 kHz): 87 MB,
  /// Apache 2.0.
  static const phonon = DownloadAsset(
    url:
        'https://huggingface.co/litert-community/phonon-31m-en/resolve/'
        '63a6170895a34600560f80dce4c70f7c90e32956/phonon_int8.litertlm',
    sha256: 'b33a9a0d65acec36762db38a2bff6d899f4aab34b196bb56d89fab5665eabebe',
  );

  /// Every model above by the name an app lists to bundle it, under
  /// `hooks.user_defines.mediapipe_audio.models` in pubspec.yaml.
  static const byName = <String, DownloadAsset>{
    'yamnet': yamnet,
    'parakeet_tdt_v3': parakeetTdtV3,
    'phonon': phonon,
  };
}
