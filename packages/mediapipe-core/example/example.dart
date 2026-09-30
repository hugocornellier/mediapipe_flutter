import 'package:mediapipe_core/mediapipe_core.dart';

/// Downloads a pinned model once, verifies its SHA-256 and reuses the cached
/// copy afterwards, including offline. Task options accept these pins directly
/// (`model: VisionModels.faceDetector`); the store is for prefetching, for
/// example during onboarding, and for clearing the cache.
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
