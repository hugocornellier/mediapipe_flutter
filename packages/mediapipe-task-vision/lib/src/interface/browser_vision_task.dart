import 'vision_types.dart';

/// Browser frame and overlay operations shared by video vision tasks.
///
/// Applications can use this interface when the task type is chosen at runtime.
/// A browser frame is released by the task after inference completes.
abstract interface class BrowserVisionTask<R> {
  /// Runs inference on one image.
  Future<R> detectImage(VisionImage image);

  /// Runs inference on a video image with an increasing timestamp.
  Future<R> detectForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  });

  /// Transfers one browser frame to the task for video inference.
  Future<R> detectBrowserFrame(
    Object frame, {
    required int width,
    required int height,
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  });

  /// Attaches a browser canvas for worker-side overlay drawing.
  Future<void> attachBrowserOverlay(Object canvas);

  /// Sets the browser overlay appearance.
  void setBrowserOverlayOptions({
    required bool connections,
    required bool points,
    bool mirrored = false,
    double scale = 1,
  });

  /// Whether the browser worker currently draws into its attached canvas.
  bool get browserOverlayActive;

  /// Releases task resources. Repeated calls are safe.
  Future<void> dispose();
}
