import 'package:mediapipe_core/mediapipe_core.dart';

import '../capabilities.dart';
import '../runner/native_tasks.dart';
import '../runner/vision_task_runner.dart';
import '../types/options.dart';
import '../types/results.dart';
import '../types/vision_types.dart';
import '../vision_task_backend.dart';

/// Google's Image Segmenter: confidence masks per category, a category mask,
/// or both.
///
/// One class on every platform. Google's native runtime serves it on a
/// worker isolate on macOS, Linux, Windows and iOS; its Android SDK and
/// browser runtime serve it through the registered platform plugin.
///
/// ```dart
/// final task = await ImageSegmenter.create(
///   ImageSegmenterOptions(model: VisionModels.imageSegmenter),
/// );
/// final result = await task.segment(VisionImage.fromFile('photo.jpg'));
/// await task.dispose();
/// ```
/// Calls run one at a time, in call order. A `Future` cannot cancel native
/// work; `dispose()` waits for work already accepted and is idempotent.
final class ImageSegmenter implements VisionTask {
  ImageSegmenter._(this._task, this.delegate);
  final VisionTaskRunner<ImageSegmenterResult> _task;

  @override
  final Delegate delegate;

  @override
  RunningMode get runningMode => _task.runningMode;

  /// Resolves the model and opens Google's task off the calling isolate.
  static Future<ImageSegmenter> create(ImageSegmenterOptions options) async {
    final runner = await VisionTaskRunner.open(
      options,
      name: 'ImageSegmenter',
      debugName: 'MediaPipe Image Segmenter',
      backend: imageSegmenterBackendFactory,
      capabilities: queryImageSegmenterCapabilities,
      native: nativeImageSegmenter,
    );
    final task = ImageSegmenter._(runner, options.delegate);
    if (runner.overlayBackend case final overlay?) {
      overlayBackends[task] = overlay;
    }
    return task;
  }

  /// Segments a still image. [rotationDegrees] is clockwise and a multiple
  /// of 90; Google's segmenter takes no region of interest.
  Future<ImageSegmenterResult> segment(
    VisionImage image, {
    int rotationDegrees = 0,
  }) => _task.image(image, rotationDegrees);

  /// Segments a video frame. Requires [RunningMode.video]; timestamps are
  /// nonnegative milliseconds that strictly increase in call order.
  Future<ImageSegmenterResult> segmentForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) => _task.video(image, rotationDegrees, timestampMilliseconds);

  @override
  Future<void> dispose() => _task.dispose();
}
