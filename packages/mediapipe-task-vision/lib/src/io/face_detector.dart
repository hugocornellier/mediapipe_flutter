import '../interface/face_detector_types.dart';
import '../vision_task_backend.dart' show faceDetectorBackendFactory;
import 'native_face_detector.dart';
import 'vision_task_runner.dart';
import 'vision_task_worker.dart';

/// Official MediaPipe Face Detector, with inference serialized on a worker isolate.
///
/// Supports CPU/Metal on macOS and with the official iOS SDK adapter.
/// Source-built iOS runtimes support CPU only.
/// Both targets support IMAGE/VIDEO modes. Await [dispose].
///
/// ```dart
/// final task = await FaceDetector.create(
///   FaceDetectorOptions(model: VisionModels.faceDetector),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.detectImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class FaceDetector {
  FaceDetector._(this._task, this.delegate);
  final VisionTaskRunner<FaceDetectorResult> _task;

  /// The official running mode selected when this detector was created.
  RunningMode get runningMode => _task.runningMode;

  /// The backend requested at creation. Fixed for the lifetime of this task.
  final VisionDelegate delegate;

  /// Load an official model and initialize MediaPipe off the calling isolate.
  static Future<FaceDetector> create(FaceDetectorOptions options) async =>
      FaceDetector._(
        await VisionTaskRunner.open(
          options,
          name: 'FaceDetector',
          debugName: 'MediaPipe Face Detector',
          android: faceDetectorBackendFactory,
          native: _createNative,
        ),
        options.delegate,
      );

  /// Detect faces with MediaPipe's own preprocessing, inference, and suppression.
  ///
  /// [rotationDegrees] is clockwise, must be a multiple of 90, and is applied by
  /// MediaPipe. Output coordinates remain relative to the input image.
  Future<FaceDetectorResult> detectImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) => _task.image(image, rotationDegrees);

  /// Process a video or camera frame on the inference worker.
  ///
  /// Requires [RunningMode.video]. Timestamps are nonnegative milliseconds
  /// and must strictly increase in submission order. A submitted timestamp is
  /// reserved even if that frame fails. Each call returns its input timestamp.
  /// For a live camera, await each call and skip frames while busy to bound delay.
  Future<FaceDetectorResult> detectForVideo(
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

NativeVisionTask<FaceDetectorResult> _createNative(
  FaceDetectorOptions options,
) => NativeFaceDetector(options);
