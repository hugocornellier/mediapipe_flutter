import 'package:mediapipe_core/mediapipe_core.dart';

/// Downloads a pinned model at run time, verifies its SHA-256 and reuses the
/// cached copy afterwards, including offline. Task options accept these pins
/// directly (`model: VisionModels.faceDetector`) and use the copy the app
/// bundles with `dart run mediapipe_core:bundle_models`; the store is for apps
/// that download instead, for example during onboarding, and for clearing the
/// cache.
Future<void> main() async {
  const model = DownloadAsset(
    url:
        'https://storage.googleapis.com/mediapipe-models/'
        'audio_classifier/yamnet/float32/1/yamnet.tflite',
    sha256: '4d8b4a53282dc83ef04e3e7dbc4fbc98082e34e44ed798e16c3a0cdd4c584faf',
  );
  final store = ModelStore();
  try {
    await store.prefetch(model);
    print('Cached ${model.url}');
  } on ModelDownloadException catch (error) {
    print('Download failed: $error');
  }
}
