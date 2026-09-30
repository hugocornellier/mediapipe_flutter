import 'vision_task_backend.dart';
import 'package:mediapipe_core/mediapipe_exception.dart';
import 'interface/browser_vision_task.dart';

/// Validation and ordering shared by every task that runs through an official
/// platform SDK adapter (browser, Android): running mode, rotation, strictly
/// increasing timestamps, frame transport and disposal.
class SdkVisionTask<R> implements BrowserVisionTask<R> {
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
  final RunningMode runningMode;

  /// Explicitly requested delegate.
  final VisionDelegate delegate;
  int? _timestamp;
  Future<void>? _disposing;

  void _check(RunningMode mode, int rotation, int? timestamp) {
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
  /// [regionOfInterest] applies only to tasks that accept one, [keypoint] only
  /// to Interactive Segmenter Legacy.
  @override
  Future<R> detectImage(
    VisionImage image, {
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
    SegmentationPoint? keypoint,
  }) async {
    _check(RunningMode.image, rotationDegrees, null);
    return _backend.detect(
      image,
      rotationDegrees,
      null,
      regionOfInterest: regionOfInterest,
      keypoint: keypoint,
    );
  }

  /// Runs VIDEO inference with a strictly increasing timestamp.
  @override
  Future<R> detectForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
  }) async {
    _check(RunningMode.video, rotationDegrees, timestampMilliseconds);
    return _backend.detect(
      image,
      rotationDegrees,
      timestampMilliseconds,
      regionOfInterest: regionOfInterest,
    );
  }

  /// Transfers ownership of a browser bitmap to the adapter for VIDEO inference.
  @override
  Future<R> detectBrowserFrame(
    Object frame, {
    required int width,
    required int height,
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) async {
    _check(RunningMode.video, rotationDegrees, timestampMilliseconds);
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

  /// Attaches an optional browser canvas; callers can keep their painter as a
  /// fallback if the browser does not support worker canvas transfer.
  @override
  Future<void> attachBrowserOverlay(Object canvas) {
    final backend = _backend;
    if (backend is! VisionTaskOverlayBackend) {
      throw UnsupportedError('Backend has no browser overlay.');
    }
    return (backend as VisionTaskOverlayBackend).attachOverlay(canvas);
  }

  /// Updates the browser overlay's connection and landmark visibility.
  @override
  void setBrowserOverlayOptions({
    required bool connections,
    required bool points,
    bool mirrored = false,
    double scale = 1,
  }) {
    final backend = _backend;
    if (backend is VisionTaskOverlayBackend) {
      (backend as VisionTaskOverlayBackend).setOverlayOptions(
        connections: connections,
        points: points,
        mirrored: mirrored,
        scale: scale,
      );
    }
  }

  /// Whether the browser worker is still drawing into its attached canvas.
  @override
  bool get browserOverlayActive =>
      _backend is VisionTaskOverlayBackend &&
      (_backend as VisionTaskOverlayBackend).overlayActive;

  /// Finishes queued requests and releases the task; repeated calls are safe.
  @override
  Future<void> dispose() => _disposing ??= _backend.dispose();
}

/// The registered browser adapter factory, or an error naming the plugin.
F requireBrowserFactory<F extends Object>(F? factory) {
  if (factory == null) {
    throw const RuntimeUnavailableException(
      'MediaPipe vision browser backend did not register.',
      fix: 'Install mediapipe_vision for the browser.',
    );
  }
  return factory;
}
