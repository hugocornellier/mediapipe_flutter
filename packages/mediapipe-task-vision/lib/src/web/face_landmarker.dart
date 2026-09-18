import '../../face_landmarker_backend.dart';
import '../interface/face_landmarker_types.dart';
import '../interface/vision_types.dart';

/// Official MediaPipe browser task installed by the Flutter web adapter.
final class FaceLandmarker {
  FaceLandmarker._(this._backend, this.runningMode, this.delegate);
  final FaceLandmarkerBackend _backend;

  /// Fixed running mode.
  final VisionRunningMode runningMode;

  /// Explicitly requested delegate.
  final VisionDelegate delegate;
  int? _timestamp;
  Future<void>? _disposing;

  /// Creates a task through the registered official browser adapter.
  static Future<FaceLandmarker> create(FaceLandmarkerOptions options) async {
    final factory = faceLandmarkerBackendFactory;
    if (factory == null) {
      throw StateError('Add mediapipe_flutter_vision_web to the Flutter app.');
    }
    return FaceLandmarker._(
      await factory(options),
      options.runningMode,
      options.delegate,
    );
  }

  void _check(VisionRunningMode mode, int rotation, int? timestamp) {
    if (_disposing != null) {
      throw StateError('FaceLandmarker has been disposed.');
    }
    if (runningMode != mode) {
      throw StateError('This method requires ${mode.name} mode.');
    }
    if (rotation % 90 != 0 || rotation < -0x80000000 || rotation > 0x7fffffff) {
      throw ArgumentError.value(
        rotation,
        'rotationDegrees',
        'Must be a C int divisible by 90',
      );
    }
    if (timestamp != null) {
      // Browser timestamps must also fit JavaScript's exact integer range.
      if (timestamp < 0 ||
          timestamp > 9007199254740 ||
          (_timestamp != null && timestamp <= _timestamp!)) {
        throw ArgumentError.value(
          timestamp,
          'timestampMilliseconds',
          'Must strictly increase and fit MediaPipe timestamps',
        );
      }
      _timestamp = timestamp;
    }
  }

  /// Runs IMAGE inference with copied pixels or a browser-accessible URL.
  Future<FaceLandmarkerResult> detectImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) async {
    _check(VisionRunningMode.image, rotationDegrees, null);
    return _backend.detect(image, rotationDegrees, null);
  }

  /// Runs VIDEO inference with a strictly increasing timestamp.
  Future<FaceLandmarkerResult> detectForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) async {
    _check(VisionRunningMode.video, rotationDegrees, timestampMilliseconds);
    return _backend.detect(image, rotationDegrees, timestampMilliseconds);
  }

  /// Transfers ownership of a browser bitmap to the adapter for VIDEO inference.
  Future<FaceLandmarkerResult> detectBrowserFrame(
    Object frame, {
    required int width,
    required int height,
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) async {
    _check(VisionRunningMode.video, rotationDegrees, timestampMilliseconds);
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Frame dimensions must be positive.');
    }
    final backend = _backend;
    if (backend is! FaceLandmarkerFrameBackend) {
      throw UnsupportedError('Backend has no browser frame transport.');
    }
    return backend.detectFrame(
      frame,
      width,
      height,
      rotationDegrees,
      timestampMilliseconds,
    );
  }

  /// Finishes queued requests and releases the task; repeated calls are safe.
  Future<void> dispose() => _disposing ??= _backend.dispose();
}
