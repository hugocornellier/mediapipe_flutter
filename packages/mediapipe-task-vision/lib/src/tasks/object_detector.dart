import 'package:mediapipe_core/mediapipe_core.dart';

import '../capabilities.dart';
import '../runner/native_tasks.dart';
import '../runner/vision_task_runner.dart';
import '../types/options.dart';
import '../types/results.dart';
import '../types/vision_types.dart';
import '../vision_task_backend.dart';

/// Google's Object Detector: a box and categories per object.
///
/// One class on every platform. Google's native runtime serves it on a
/// worker isolate on macOS, Linux, Windows and iOS; its Android SDK and
/// browser runtime serve it through the registered platform plugin. Metal
/// needs a float model, such as the pinned EfficientDet-Lite0 float32 one.
///
/// ```dart
/// final task = await ObjectDetector.create(
///   ObjectDetectorOptions(model: VisionModels.objectDetector),
/// );
/// final result = await task.detect(VisionImage.fromFile('photo.jpg'));
/// await task.dispose();
/// ```
/// Calls run one at a time, in call order. A `Future` cannot cancel native
/// work; `dispose()` waits for work already accepted and is idempotent.
final class ObjectDetector implements VisionTask {
  ObjectDetector._(this._task, this.delegate);
  final VisionTaskRunner<ObjectDetectorResult> _task;

  @override
  final Delegate delegate;

  @override
  RunningMode get runningMode => _task.runningMode;

  /// Resolves the model and opens Google's task off the calling isolate.
  static Future<ObjectDetector> create(ObjectDetectorOptions options) async {
    final runner = await VisionTaskRunner.open(
      options,
      name: 'ObjectDetector',
      debugName: 'MediaPipe Object Detector',
      backend: objectDetectorBackendFactory,
      capabilities: queryObjectDetectorCapabilities,
      native: nativeObjectDetector,
    );
    final task = ObjectDetector._(runner, options.delegate);
    if (runner.overlayBackend case final overlay?) {
      overlayBackends[task] = overlay;
    }
    return task;
  }

  /// Detects objects in a still image. [rotationDegrees] is clockwise and a
  /// multiple of 90; Google applies it, and coordinates stay in the input's
  /// frame.
  Future<ObjectDetectorResult> detect(
    VisionImage image, {
    int rotationDegrees = 0,
  }) => _task.image(image, rotationDegrees);

  /// Detects objects in a video frame. Requires [RunningMode.video];
  /// timestamps are nonnegative milliseconds that strictly increase in call
  /// order, and a submitted timestamp stays reserved even if that frame
  /// fails.
  Future<ObjectDetectorResult> detectForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) => _task.video(image, rotationDegrees, timestampMilliseconds);

  @override
  Future<void> dispose() => _task.dispose();
}
