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

/// Creates Google's Audio Classifier from `options` named as in Google's
/// JavaScript API, plus `modelBytes` (a `Uint8List`) or `modelPath` (a URL).
///
/// Installed by this package's platform code in browsers and on Android;
/// null where the package runs Google's runtime itself.
Future<AudioTaskBackend> Function(Map<String, Object?> options)?
audioTaskBackendFactory;

/// Google's Audio Classifier in its audio stream mode, created and run by a
/// platform backend.
abstract interface class AudioStreamBackend {
  /// Hands one block to Google's stream: [samples] interleaved by
  /// [channels], at [sampleRate], stamped [timestampMilliseconds]. Returns at
  /// once; Google's refusal arrives on [results] as an error.
  void send(
    Float32List samples,
    double sampleRate,
    int channels,
    int timestampMilliseconds,
  );

  /// One result per window, as JSON values in the shape of Google's
  /// JavaScript API, each with Google's own `timestampMs`. A failure arrives
  /// as an error.
  Stream<Map<String, Object?>> get results;

  /// Closes Google's task, which flushes the tail: its result arrives on
  /// [results], which then closes, before this completes.
  Future<void> dispose();
}

/// Creates Google's Audio Classifier in audio stream mode from `options`, as
/// [audioTaskBackendFactory] does in clips mode.
///
/// Installed by this package's Android plugin. Browsers have no stream in
/// Google's runtime, so there none is installed and the package emulates
/// the stream on [audioTaskBackendFactory]'s clips mode.
Future<AudioStreamBackend> Function(Map<String, Object?> options)?
audioStreamBackendFactory;
