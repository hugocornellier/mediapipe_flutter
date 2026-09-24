/// The hook through which mediapipe_flutter_audio_web runs Audio Classifier
/// in a browser.
library;

import 'dart:typed_data';

/// Google's browser Audio Classifier, created and run on a worker.
abstract interface class AudioWebTask {
  /// Classifies mono [samples] at [sampleRate] and returns Google's
  /// JavaScript results (one per chunk), as JSON values.
  Future<List<Object?>> classify(Float32List samples, double sampleRate);

  /// Waits for queued requests, then closes Google's task.
  Future<void> dispose();
}

/// Creates Google's Audio Classifier from [options] named as in Google's
/// JavaScript API, plus `modelBytes` (a `Uint8List`) or `modelPath` (a URL).
///
/// Installed by the mediapipe_flutter_audio_web plugin; null elsewhere.
Future<AudioWebTask> Function(Map<String, Object?> options)?
audioWebTaskFactory;
