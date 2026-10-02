import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:mediapipe_core/mediapipe_core.dart';

import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../capabilities/official_runtime_io.dart';
import '../runner/native_interface.dart';
import '../types/options.dart';
import '../types/results.dart';
import 'native_ios_sdk.dart';
import 'native_vision_image.dart';
import 'native_vision_task.dart';

/// Google's Pose Landmarker on its worker isolate.
final class NativePoseLandmarker
    implements NativeVisionTask<PoseLandmarkerResult> {
  /// Creates the task with the requested delegate, mode and masks.
  NativePoseLandmarker(PoseLandmarkerOptions options)
    : _gpu = options.delegate == Delegate.gpu,
      _masks = options.outputSegmentationMasks {
    using((arena) {
      final native = arena<mp.MpPoseLandmarkerOptions>();
      setVisionBaseOptions(
        arena,
        native.ref.base_options,
        options,
        officialGpu: true,
      );
      native.ref.running_mode = nativeRunningMode(options.runningMode);
      native.ref
        ..num_poses = options.numPoses
        ..min_pose_detection_confidence = options.minPoseDetectionConfidence
        ..min_pose_presence_confidence = options.minPosePresenceConfidence
        ..min_tracking_confidence = options.minTrackingConfidence
        ..output_segmentation_masks = options.outputSegmentationMasks;
      final output = arena<mp.MpPoseLandmarkerPtr>();
      checkVisionCreate(
        (error) => mp.MpPoseLandmarkerCreate(native, output, error),
        gpu: _gpu,
      );
      _task = output.value;
    });
  }
  final bool _gpu;
  final bool _masks;
  mp.MpPoseLandmarkerPtr _task = nullptr;
  late final IosBgraStorage? _iosBgra =
      hasOfficialIosVisionRuntime() && iosImageStorageMode != 0
      ? IosBgraStorage(iosImageStorageMode)
      : null;

  @override
  PoseLandmarkerResult process(VisionTaskInput input) => using((arena) {
    final (source, rotation, timestamp, _) = input;
    final image = createVisionImage(
      arena,
      source,
      expandRgbForGpu: _gpu,
      checked: checkVisionCall,
      iosBgra: _iosBgra,
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
    try {
      checkVisionCall((error) => mp.MpPoseLandmarkerClose(task, error));
    } finally {
      _iosBgra?.close();
    }
  }
}
