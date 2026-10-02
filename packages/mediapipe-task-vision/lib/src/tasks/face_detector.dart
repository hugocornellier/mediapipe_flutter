import 'package:mediapipe_core/mediapipe_core.dart';

import '../runner/native_tasks.dart';
import '../runner/vision_task_runner.dart';
import '../types/options.dart';
import '../types/results.dart';
import '../types/vision_types.dart';
import '../vision_task_backend.dart';

/// Google's Face Detector: boxes, scores and six keypoints per face.
///
/// One class on every platform. Google's native runtime serves it on a
/// worker isolate on macOS, Linux, Windows and iOS; its Android SDK and
/// browser runtime serve it through the registered platform plugin.
///
/// ```dart
/// final task = await FaceDetector.create(
///   FaceDetectorOptions(model: VisionModels.faceDetector),
/// );
/// final result = await task.detect(VisionImage.fromFile('photo.jpg'));
/// await task.dispose();
/// ```
/// Calls run one at a time, in call order. A `Future` cannot cancel native
/// work; `dispose()` waits for work already accepted and is idempotent.
final class FaceDetector implements VisionTask {
  FaceDetector._(this._task, this.delegate);
  final VisionTaskRunner<FaceDetectorResult> _task;

  @override
  final Delegate delegate;

  @override
  RunningMode get runningMode => _task.runningMode;

  /// Resolves the model and opens Google's task off the calling isolate.
  static Future<FaceDetector> create(FaceDetectorOptions options) async {
    final runner = await VisionTaskRunner.open(
      options,
      name: 'FaceDetector',
      debugName: 'MediaPipe Face Detector',
      backend: faceDetectorBackendFactory,
      native: nativeFaceDetector,
    );
    final task = FaceDetector._(runner, options.delegate);
    if (runner.overlayBackend case final overlay?) {
      overlayBackends[task] = overlay;
    }
    return task;
  }

  /// Detects faces in a still image. [rotationDegrees] is clockwise and a
  /// multiple of 90; Google applies it, and coordinates stay in the input's
  /// frame.
  Future<FaceDetectorResult> detect(
    VisionImage image, {
    int rotationDegrees = 0,
  }) => _task.image(image, rotationDegrees);

  /// Detects faces in a video frame. Requires [RunningMode.video]; timestamps
  /// are nonnegative milliseconds that strictly increase in call order, and
  /// a submitted timestamp stays reserved even if that frame fails.
  Future<FaceDetectorResult> detectForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) => _task.video(image, rotationDegrees, timestampMilliseconds);

  @override
  Future<void> dispose() => _task.dispose();
}
