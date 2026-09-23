import '../../vision_task_backend.dart';
import '../sdk_vision_task.dart';

/// Official MediaPipe browser Holistic Landmarker installed by the web adapter.
final class HolisticLandmarker extends SdkVisionTask<HolisticLandmarkerResult> {
  HolisticLandmarker._(super.backend, super.runningMode, super.delegate)
    : super(name: 'HolisticLandmarker');

  /// Creates a task through the registered official browser adapter.
  static Future<HolisticLandmarker> create(
    HolisticLandmarkerOptions options,
  ) async => HolisticLandmarker._(
    await requireBrowserFactory(holisticLandmarkerBackendFactory)(options),
    options.runningMode,
    options.delegate,
  );
}
