import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../../capabilities.dart';
import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../interface/landmark_task_types.dart';
import 'native_vision_image.dart';
import 'native_vision_task.dart';
import 'vision_task_worker.dart';

/// Official PoseLandmarker, with owned results and serialized image/video inference.
final class PoseLandmarker {
  PoseLandmarker._(this._worker, this.delegate);
  final VisionTaskWorker<PoseLandmarkerResult> _worker;

  /// Requested backend, fixed until disposal.
  final VisionDelegate delegate;

  /// Mode selected when creating this task.
  VisionRunningMode get runningMode => _worker.runningMode;

  /// Load a compatible task bundle on a worker isolate.
  static Future<PoseLandmarker> create(PoseLandmarkerOptions options) async {
    final capabilities = await queryLandmarkTaskCapabilities();
    if (!capabilities.supportedDelegates.contains(options.delegate)) {
      throw UnsupportedError(
        capabilities.unavailableReasons[options.delegate]!,
      );
    }
    return PoseLandmarker._(
      await VisionTaskWorker.create(
        options,
        _createNative,
        'MediaPipe PoseLandmarker',
      ),
      options.delegate,
    );
  }

  /// Process one still image with official rotation preprocessing.
  Future<PoseLandmarkerResult> detectImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) => _worker.processImage(image, rotationDegrees, null);

  /// Process a video frame with a strictly increasing millisecond timestamp.
  Future<PoseLandmarkerResult> detectForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) =>
      _worker.processVideo(image, rotationDegrees, timestampMilliseconds, null);

  /// Drain queued requests and release native resources exactly once.
  Future<void> dispose() => _worker.dispose();
}

NativeVisionTask<PoseLandmarkerResult> _createNative(
  PoseLandmarkerOptions options,
) => _NativePoseLandmarker(options);

final class _NativePoseLandmarker
    implements NativeVisionTask<PoseLandmarkerResult> {
  _NativePoseLandmarker(PoseLandmarkerOptions options)
    : _gpu = options.delegate == VisionDelegate.gpu,
      _masks = options.outputSegmentationMasks {
    using((arena) {
      final native = arena<mp.MpPoseLandmarkerOptions>();
      setVisionBaseOptions(arena, native.ref.base_options, options);
      native.ref.running_mode = nativeVisionRunningMode(options.runningMode);
      native.ref
        ..num_poses = options.numPoses
        ..min_pose_detection_confidence = options.minPoseDetectionConfidence
        ..min_pose_presence_confidence = options.minPosePresenceConfidence
        ..min_tracking_confidence = options.minTrackingConfidence
        ..output_segmentation_masks = options.outputSegmentationMasks;
      final output = arena<mp.MpPoseLandmarkerPtr>();
      checkVisionCall(
        (error) => mp.MpPoseLandmarkerCreate(native, output, error),
      );
      _task = output.value;
    });
  }
  final bool _gpu;
  final bool _masks;
  mp.MpPoseLandmarkerPtr _task = nullptr;

  @override
  PoseLandmarkerResult process(VisionTaskInput input) => using((arena) {
    final (source, rotation, timestamp, _) = input;
    final image = createVisionImage(
      arena,
      source,
      expandRgbForGpu: _gpu,
      checked: checkVisionCall,
    );
    try {
      final processing = visionProcessingOptions(arena, rotation, null);
      final result = arena<mp.MpPoseLandmarkerResult>();
      if (timestamp == null) {
        checkVisionCall(
          (error) => mp.MpPoseLandmarkerDetectImage(
            _task,
            image,
            processing,
            result,
            error,
          ),
        );
      } else {
        checkVisionCall(
          (error) => mp.MpPoseLandmarkerDetectForVideo(
            _task,
            image,
            processing,
            timestamp,
            result,
            error,
          ),
        );
      }
      try {
        return PoseLandmarkerResult(
          poseLandmarks: [
            for (var i = 0; i < result.ref.pose_landmarks_count; i++)
              copyVisionNormalizedLandmarks(result.ref.pose_landmarks[i]),
          ],
          poseWorldLandmarks: [
            for (var i = 0; i < result.ref.pose_world_landmarks_count; i++)
              copyVisionWorldLandmarks(result.ref.pose_world_landmarks[i]),
          ],
          segmentationMasks: _masks && result.ref.segmentation_masks_count > 0
              ? [
                  for (var i = 0; i < result.ref.segmentation_masks_count; i++)
                    copyVisionConfidenceMask(
                      arena,
                      result.ref.segmentation_masks[i],
                    ),
                ]
              : null,
          imageWidth: mp.MpImageGetWidth(image),
          imageHeight: mp.MpImageGetHeight(image),
          timestampMilliseconds: timestamp,
        );
      } finally {
        mp.MpPoseLandmarkerCloseResult(result);
      }
    } finally {
      mp.MpImageFree(image);
    }
  });

  @override
  void close() {
    if (_task == nullptr) return;
    final task = _task;
    _task = nullptr;
    checkVisionCall((error) => mp.MpPoseLandmarkerClose(task, error));
  }
}
