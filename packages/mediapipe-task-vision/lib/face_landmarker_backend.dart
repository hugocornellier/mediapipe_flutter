/// Extension point for platform SDK adapters. Applications use FaceLandmarker.
library;

import 'src/interface/face_landmarker_types.dart';
import 'src/interface/vision_types.dart';

/// A serialized, asynchronous adapter to an official platform SDK.
abstract interface class FaceLandmarkerBackend {
  /// Completes with copied results; requests and disposal retain submission order.
  Future<FaceLandmarkerResult> detect(
    VisionImage image,
    int rotationDegrees,
    int? timestampMilliseconds,
  );

  /// Finishes queued requests and releases the SDK task on its owning thread.
  Future<void> dispose();
}

/// Optional browser-frame transport, keeping browser objects out of native APIs.
abstract interface class FaceLandmarkerFrameBackend
    implements FaceLandmarkerBackend {
  /// Takes ownership of one browser frame and releases it after inference.
  Future<FaceLandmarkerResult> detectFrame(
    Object frame,
    int width,
    int height,
    int rotationDegrees,
    int timestampMilliseconds,
  );
}

/// Installed by a platform plugin before the first task is created.
Future<FaceLandmarkerBackend> Function(FaceLandmarkerOptions)?
faceLandmarkerBackendFactory;
