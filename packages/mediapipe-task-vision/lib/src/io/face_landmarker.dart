import '../face_landmarker_backend.dart';
import '../interface/face_landmarker_types.dart';
import 'native_face_landmarker.dart';
import 'vision_task_runner.dart';
import 'vision_task_worker.dart';

/// Official MediaPipe Face Landmarker, with inference serialized on a worker isolate.
///
/// Supports CPU/Metal on macOS and with the official iOS SDK adapter.
/// Android CPU/GPU uses the mediapipe_vision Flutter plugin.
/// Source-built iOS runtimes support CPU only.
/// Both targets support IMAGE/VIDEO modes. Await [dispose].
///
/// ```dart
/// final task = await FaceLandmarker.create(
///   FaceLandmarkerOptions(model: VisionModels.faceLandmarker),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.detectImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class FaceLandmarker {
  FaceLandmarker._(this._task, this.delegate);
  final VisionTaskRunner<FaceLandmarkerResult> _task;

  /// The official running mode selected when this detector was created.
  RunningMode get runningMode => _task.runningMode;

  /// The backend requested at creation. Fixed for the lifetime of this task.
  final VisionDelegate delegate;

  /// Load an official model and initialize MediaPipe off the calling isolate.
  static Future<FaceLandmarker> create(FaceLandmarkerOptions options) async =>
      FaceLandmarker._(
        await VisionTaskRunner.open(
          options,
          name: 'FaceLandmarker',
          debugName: 'MediaPipe Face Landmarker',
          android: faceLandmarkerBackendFactory,
          native: _createNative,
        ),
        options.delegate,
      );

  /// Locate face landmarks with MediaPipe's unmodified task pipeline.
  ///
  /// [rotationDegrees] is clockwise, must be a multiple of 90, and is applied by
  /// MediaPipe. Output coordinates remain relative to the input image.
  Future<FaceLandmarkerResult> detectImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) => _task.image(image, rotationDegrees);

  /// Process a video or camera frame on the inference worker.
  ///
  /// Requires [RunningMode.video]. Timestamps are nonnegative milliseconds
  /// and must strictly increase in submission order. A submitted timestamp is
  /// reserved even if that frame fails. Each call returns its input timestamp.
  /// For a live camera, await each call and skip frames while busy to bound delay.
  Future<FaceLandmarkerResult> detectForVideo(
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

NativeVisionTask<FaceLandmarkerResult> _createNative(
  FaceLandmarkerOptions options,
) => NativeFaceLandmarker(options);
