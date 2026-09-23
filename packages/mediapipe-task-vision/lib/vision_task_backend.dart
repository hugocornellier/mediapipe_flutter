/// Extension point for platform SDK adapters. Applications use the task classes.
library;

import 'src/interface/landmark_task_types.dart';

export 'src/interface/landmark_codec.dart';
export 'src/interface/landmark_task_types.dart';

/// A serialized, asynchronous adapter to one task of an official platform SDK.
abstract interface class VisionTaskBackend<R> {
  /// Completes with copied results; requests and disposal retain submission order.
  Future<R> detect(
    VisionImage image,
    int rotationDegrees,
    int? timestampMilliseconds,
  );

  /// Finishes queued requests and releases the SDK task on its owning thread.
  Future<void> dispose();
}

/// Optional browser-frame transport, keeping browser objects out of native APIs.
abstract interface class VisionTaskFrameBackend<R>
    implements VisionTaskBackend<R> {
  /// Takes ownership of one browser frame and releases it after inference.
  Future<R> detectFrame(
    Object frame,
    int width,
    int height,
    int rotationDegrees,
    int timestampMilliseconds,
  );
}

/// Installed by a platform plugin before the first HandLandmarker is created.
Future<VisionTaskBackend<HandLandmarkerResult>> Function(HandLandmarkerOptions)?
handLandmarkerBackendFactory;
