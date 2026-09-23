import '../vision_task_backend.dart';

/// Validation and ordering shared by every task that runs through an official
/// platform SDK adapter (browser, Android): running mode, rotation, strictly
/// increasing timestamps, frame transport and disposal.
class SdkVisionTask<R> {
  /// Wraps [_backend]; [name] appears in errors, [maxTimestamp] bounds VIDEO
  /// timestamps for the runtime behind the adapter.
  SdkVisionTask(
    this._backend,
    this.runningMode,
    this.delegate, {
    required this.name,
    this.maxTimestamp = browserMaxTimestamp,
  });
  final VisionTaskBackend<R> _backend;

  /// Task name used in errors.
  final String name;

  /// Largest accepted VIDEO timestamp in milliseconds.
  final int maxTimestamp;

  /// Browser timestamps must also fit JavaScript's exact integer range.
  static const browserMaxTimestamp = 9007199254740;

  /// Fixed running mode.
  final VisionRunningMode runningMode;

  /// Explicitly requested delegate.
  final VisionDelegate delegate;
  int? _timestamp;
  Future<void>? _disposing;

  void _check(VisionRunningMode mode, int rotation, int? timestamp) {
    if (_disposing != null) {
      throw StateError('$name has been disposed.');
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
      if (timestamp < 0 ||
          timestamp > maxTimestamp ||
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
  Future<R> detectImage(VisionImage image, {int rotationDegrees = 0}) async {
    _check(VisionRunningMode.image, rotationDegrees, null);
    return _backend.detect(image, rotationDegrees, null);
  }

  /// Runs VIDEO inference with a strictly increasing timestamp.
  Future<R> detectForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) async {
    _check(VisionRunningMode.video, rotationDegrees, timestampMilliseconds);
    return _backend.detect(image, rotationDegrees, timestampMilliseconds);
  }

  /// Transfers ownership of a browser bitmap to the adapter for VIDEO inference.
  Future<R> detectBrowserFrame(
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
    if (backend is! VisionTaskFrameBackend<R>) {
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

/// The registered browser adapter factory, or an error naming the plugin.
F requireBrowserFactory<F extends Object>(F? factory) {
  if (factory == null) {
    throw StateError('Add mediapipe_flutter_vision_web to the Flutter app.');
  }
  return factory;
}
