/// A task on an official platform SDK adapter (Google's browser runtime or
/// Android SDK): the shared checks, then the backend, in submission order.
library;

import '../types/vision_types.dart';
import '../vision_task_backend.dart';
import 'checks.dart';

/// Validation and ordering for every task that runs through a backend.
final class SdkVisionTask<R> {
  /// Wraps [_backend]; [name] appears in errors.
  SdkVisionTask(this._backend, RunningMode runningMode, {required String name})
    : _checks = VisionTaskChecks(name, runningMode);

  final VisionTaskBackend<R> _backend;
  final VisionTaskChecks _checks;
  Future<void>? _disposing;

  /// The backend's browser overlay, when it draws.
  VisionTaskOverlayBackend? get overlayBackend => switch (_backend) {
    final VisionTaskOverlayBackend overlay => overlay,
    _ => null,
  };

  /// IMAGE inference; [regionOfInterest] only for the tasks that accept one.
  Future<R> image(
    VisionImage image, {
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
  }) async {
    _checks.image(rotationDegrees);
    return _backend.detect(
      image,
      rotationDegrees,
      null,
      regionOfInterest: regionOfInterest,
    );
  }

  // TODO: Add LIVE_STREAM beside video() when it is split from VIDEO,
  // for the Android adapter and the web. See RunningMode.liveStream.
  /// VIDEO inference with a strictly increasing timestamp.
  Future<R> video(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
    VisionRegionOfInterest? regionOfInterest,
  }) async {
    _checks.video(rotationDegrees, timestampMilliseconds);
    return _backend.detect(
      image,
      rotationDegrees,
      timestampMilliseconds,
      regionOfInterest: regionOfInterest,
    );
  }

  /// Finishes queued requests and releases the task; repeated calls are safe.
  Future<void> dispose() {
    _checks.markDisposing();
    return _disposing ??= _backend.dispose();
  }
}
