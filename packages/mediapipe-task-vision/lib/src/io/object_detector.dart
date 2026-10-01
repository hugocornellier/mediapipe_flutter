import '../../capabilities.dart';

import '../interface/object_detector_types.dart';
import '../vision_task_backend.dart' show objectDetectorBackendFactory;
import 'native_object_detector.dart';
import 'vision_task_runner.dart';
import 'vision_task_worker.dart';

/// Official MediaPipe Object Detector, with inference serialized on a worker isolate.
///
/// Supports CPU/Metal on macOS arm64. Both IMAGE and VIDEO modes are supported.
/// Metal requires a float model; the pinned EfficientDet-Lite0 float32 model in
/// `models.dart` is one. Await [dispose].
///
/// ```dart
/// final task = await ObjectDetector.create(
///   ObjectDetectorOptions(model: VisionModels.objectDetector),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.detectImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class ObjectDetector {
  ObjectDetector._(this._task, this.delegate);
  final VisionTaskRunner<ObjectDetectorResult> _task;

  /// The official running mode selected when this detector was created.
  RunningMode get runningMode => _task.runningMode;

  /// The backend requested at creation. Fixed for the lifetime of this task.
  final VisionDelegate delegate;

  /// Load an official model and initialize MediaPipe off the calling isolate.
  static Future<ObjectDetector> create(ObjectDetectorOptions options) async =>
      ObjectDetector._(
        await VisionTaskRunner.open(
          options,
          name: 'ObjectDetector',
          debugName: 'MediaPipe Object Detector',
          android: objectDetectorBackendFactory,
          capabilities: queryObjectDetectorCapabilities,
          native: _createNative,
        ),
        options.delegate,
      );

  /// Detect objects with MediaPipe's own preprocessing, inference, and suppression.
  ///
  /// [rotationDegrees] is clockwise, must be a multiple of 90, and is applied by
  /// MediaPipe. Output coordinates remain relative to the input image.
  Future<ObjectDetectorResult> detectImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) => _task.image(image, rotationDegrees);

  /// Process a video or camera frame on the inference worker.
  ///
  /// Requires [RunningMode.video]. Timestamps are nonnegative milliseconds
  /// and must strictly increase in submission order. A submitted timestamp is
  /// reserved even if that frame fails. Each call returns its input timestamp.
  /// For a live camera, await each call and skip frames while busy to bound delay.
  Future<ObjectDetectorResult> detectForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) => _task.video(image, rotationDegrees, timestampMilliseconds);

  /// Finish queued requests, close the native task, and stop its worker.
  ///
  /// Repeated calls return the same completion. New detections are rejected as
  /// soon as disposal starts.
  Future<void> dispose() => _task.dispose();
}

NativeVisionTask<ObjectDetectorResult> _createNative(
  ObjectDetectorOptions options,
) => NativeObjectDetector(options);
