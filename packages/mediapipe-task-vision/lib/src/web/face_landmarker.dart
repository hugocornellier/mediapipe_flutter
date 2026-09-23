import '../../face_landmarker_backend.dart';
import '../interface/face_landmarker_types.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser task installed by the Flutter web adapter.
final class FaceLandmarker extends SdkVisionTask<FaceLandmarkerResult> {
  FaceLandmarker._(super.backend, super.runningMode, super.delegate)
    : super(name: 'FaceLandmarker');

  /// Creates a task through the registered official browser adapter.
  static Future<FaceLandmarker> create(FaceLandmarkerOptions options) async =>
      FaceLandmarker._(
        await requireBrowserFactory(faceLandmarkerBackendFactory)(options),
        options.runningMode,
        options.delegate,
      );
}
