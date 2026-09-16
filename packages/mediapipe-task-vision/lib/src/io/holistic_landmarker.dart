import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../../capabilities.dart';
import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../interface/holistic_landmarker_types.dart';
import 'native_vision_image.dart';
import 'native_vision_task.dart';
import 'vision_task_worker.dart';

/// Official Holistic Landmarker with serialized, owned image/video results.
final class HolisticLandmarker {
  HolisticLandmarker._(this._worker, this.delegate);
  final VisionTaskWorker<HolisticLandmarkerResult> _worker;

  /// Requested backend, fixed until disposal.
  final VisionDelegate delegate;

  /// Mode selected when creating this task.
  VisionRunningMode get runningMode => _worker.runningMode;

  /// Load a compatible combined task bundle on a worker isolate.
  static Future<HolisticLandmarker> create(
    HolisticLandmarkerOptions options,
  ) async {
    final capabilities = await queryLandmarkTaskCapabilities();
    if (!capabilities.supportedDelegates.contains(options.delegate)) {
      throw UnsupportedError(
        capabilities.unavailableReasons[options.delegate]!,
      );
    }
    return HolisticLandmarker._(
      await VisionTaskWorker.create(
        options,
        _createNative,
        'MediaPipe Holistic Landmarker',
      ),
      options.delegate,
    );
  }

  /// Detect face, pose and hand landmarks in a still image.
  Future<HolisticLandmarkerResult> detectImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) => _worker.processImage(image, rotationDegrees, null);

  /// Detect landmarks in a frame with a strictly increasing timestamp.
  Future<HolisticLandmarkerResult> detectForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) =>
      _worker.processVideo(image, rotationDegrees, timestampMilliseconds, null);

  /// Drain queued requests and release native resources exactly once.
  Future<void> dispose() => _worker.dispose();
}

NativeVisionTask<HolisticLandmarkerResult> _createNative(
  HolisticLandmarkerOptions options,
) => _NativeHolisticLandmarker(options);

final class _NativeHolisticLandmarker
    implements NativeVisionTask<HolisticLandmarkerResult> {
  _NativeHolisticLandmarker(HolisticLandmarkerOptions options)
    : _gpu = options.delegate == VisionDelegate.gpu {
    using((arena) {
      final native = arena<mp.MpHolisticLandmarkerOptions>();
      setVisionBaseOptions(arena, native.ref.base_options, options);
      native.ref
        ..running_mode = nativeVisionRunningMode(options.runningMode)
        ..min_face_detection_confidence = options.minFaceDetectionConfidence
        ..min_face_suppression_threshold = options.minFaceSuppressionThreshold
        ..min_face_presence_confidence = options.minFacePresenceConfidence
        ..output_face_blendshapes = options.outputFaceBlendshapes
        ..output_pose_segmentation_masks = options.outputPoseSegmentationMask;
      // Google's 1.0.0 wheel places the hand threshold AFTER all pose fields;
      // the same-version open-source header places it BEFORE them. Both have
      // identical size, so adapt the four float slots for the pinned wheels.
      if (Platform.isLinux || Platform.isWindows) {
        native.ref
          ..min_hand_landmarks_confidence = options.minPoseDetectionConfidence
          ..min_pose_detection_confidence = options.minPoseSuppressionThreshold
          ..min_pose_suppression_threshold = options.minPosePresenceConfidence
          ..min_pose_presence_confidence = options.minHandLandmarksConfidence;
      } else {
        native.ref
          ..min_hand_landmarks_confidence = options.minHandLandmarksConfidence
          ..min_pose_detection_confidence = options.minPoseDetectionConfidence
          ..min_pose_suppression_threshold = options.minPoseSuppressionThreshold
          ..min_pose_presence_confidence = options.minPosePresenceConfidence;
      }
      final output = arena<mp.MpHolisticLandmarkerPtr>();
      checkVisionCall(
        (error) => mp.MpHolisticLandmarkerCreate(native, output, error),
      );
      _task = output.value;
    });
  }
  final bool _gpu;
  mp.MpHolisticLandmarkerPtr _task = nullptr;
  @override
  HolisticLandmarkerResult process(VisionTaskInput input) => using((arena) {
    final (source, rotation, timestamp, _, _) = input;
    final image = createVisionImage(
      arena,
      source,
      expandRgbForGpu: _gpu,
      checked: checkVisionCall,
    );
    try {
      final result = arena<mp.MpHolisticLandmarkerResult>();
      final processing = visionProcessingOptions(arena, rotation, null);
      if (timestamp == null) {
        checkVisionCall(
          (error) => mp.MpHolisticLandmarkerDetectImage(
            _task,
            image,
            processing,
            result,
            error,
          ),
        );
      } else {
        checkVisionCall(
          (error) => mp.MpHolisticLandmarkerDetectForVideo(
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
        return HolisticLandmarkerResult(
          faceLandmarks: copyVisionNormalizedLandmarks(
            result.ref.face_landmarks,
          ),
          poseLandmarks: copyVisionNormalizedLandmarks(
            result.ref.pose_landmarks,
          ),
          poseWorldLandmarks: copyVisionWorldLandmarks(
            result.ref.pose_world_landmarks,
          ),
          leftHandLandmarks: copyVisionNormalizedLandmarks(
            result.ref.left_hand_landmarks,
          ),
          rightHandLandmarks: copyVisionNormalizedLandmarks(
            result.ref.right_hand_landmarks,
          ),
          leftHandWorldLandmarks: copyVisionWorldLandmarks(
            result.ref.left_hand_world_landmarks,
          ),
          rightHandWorldLandmarks: copyVisionWorldLandmarks(
            result.ref.right_hand_world_landmarks,
          ),
          faceBlendshapes: result.ref.face_blendshapes.categories_count == 0
              ? null
              : [
                  for (
                    var i = 0;
                    i < result.ref.face_blendshapes.categories_count;
                    i++
                  )
                    copyVisionCategory(
                      result.ref.face_blendshapes.categories[i],
                    ),
                ],
          poseSegmentationMask: result.ref.pose_segmentation_mask == nullptr
              ? null
              : copyVisionConfidenceMask(
                  arena,
                  result.ref.pose_segmentation_mask,
                ),
          imageWidth: mp.MpImageGetWidth(image),
          imageHeight: mp.MpImageGetHeight(image),
          timestampMilliseconds: timestamp,
        );
      } finally {
        mp.MpHolisticLandmarkerCloseResult(result);
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
    checkVisionCall((error) => mp.MpHolisticLandmarkerClose(task, error));
  }
}
