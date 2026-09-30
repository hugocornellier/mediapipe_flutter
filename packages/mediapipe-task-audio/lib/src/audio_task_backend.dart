/// The hook through which this package's platform code runs Audio Classifier
/// on Google's runtime.
library;

import 'dart:typed_data';

/// Google's Audio Classifier, created and run by a platform backend.
abstract interface class AudioTaskBackend {
  /// Classifies mono [samples] at [sampleRate] and returns Google's
  /// JavaScript results (one per chunk), as JSON values.
  Future<List<Object?>> classify(Float32List samples, double sampleRate);

  /// Waits for queued requests, then closes Google's task.
  Future<void> dispose();
}

/// Creates Google's Audio Classifier from [options] named as in Google's
/// JavaScript API, plus `modelBytes` (a `Uint8List`) or `modelPath` (a URL).
///
/// Installed by this package's platform code in browsers and on Android;
/// null where the package runs Google's runtime itself.
Future<AudioTaskBackend> Function(Map<String, Object?> options)?
audioTaskBackendFactory;
