import 'dart:ffi';

import 'package:ffi/ffi.dart';
import '../../capabilities.dart';
import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../vision_task_backend.dart';
import '../capabilities/official_runtime_io.dart';
import 'native_ios_sdk.dart';
import 'native_vision_image.dart';
import 'native_vision_task.dart';
import 'vision_task_runner.dart';
import 'vision_task_worker.dart';

/// Official Holistic Landmarker with serialized, owned image/video results.
///
/// On Android, a registered official SDK adapter
/// (`mediapipe_vision`) runs the task; elsewhere Google's
/// native runtime runs it on a worker isolate.
///
/// ```dart
/// final task = await HolisticLandmarker.create(
///   HolisticLandmarkerOptions(model: VisionModels.holisticLandmarker),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.detectImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class HolisticLandmarker {
  HolisticLandmarker._(this._task, this.delegate);
  final VisionTaskRunner<HolisticLandmarkerResult> _task;

  /// Requested backend, fixed until disposal.
  final VisionDelegate delegate;

  /// Mode selected when creating this task.
  RunningMode get runningMode => _task.runningMode;

  /// Load a compatible task bundle on a worker isolate.
  static Future<HolisticLandmarker> create(
    HolisticLandmarkerOptions options,
  ) async => HolisticLandmarker._(
    await VisionTaskRunner.open(
      options,
      name: 'HolisticLandmarker',
      debugName: 'MediaPipe Holistic Landmarker',
      android: holisticLandmarkerBackendFactory,
      capabilities: queryHolisticLandmarkerCapabilities,
      native: _createNative,
    ),
    options.delegate,
  );

  /// Detect face, pose and hand landmarks in a still image.
  Future<HolisticLandmarkerResult> detectImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) => _task.image(image, rotationDegrees);

  /// Detect landmarks in a frame with a strictly increasing timestamp.
  Future<HolisticLandmarkerResult> detectForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) => _task.video(image, rotationDegrees, timestampMilliseconds);

  /// Drain queued requests and release native resources exactly once.
  Future<void> dispose() => _task.dispose();
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
      setVisionBaseOptions(
        arena,
        native.ref.base_options,
        options,
        officialGpu: true,
      );
      native.ref
        ..running_mode = nativeRunningMode(options.runningMode)
        ..min_face_detection_confidence = options.minFaceDetectionConfidence
        ..min_face_suppression_threshold = options.minFaceSuppressionThreshold
        ..min_face_presence_confidence = options.minFacePresenceConfidence
        ..output_face_blendshapes = options.outputFaceBlendshapes
        ..output_pose_segmentation_masks = options.outputPoseSegmentationMask
        // Every official library, including the wheels' (Linux, Windows and
        // the official macOS runtime), reads the header's order. Google's
        // Python ctypes do not, so its references are generated with the
        // header's order too (UP-005, tool/holistic_threshold_order_probe.py).
        ..min_hand_landmarks_confidence = options.minHandLandmarksConfidence
        ..min_pose_detection_confidence = options.minPoseDetectionConfidence
        ..min_pose_suppression_threshold = options.minPoseSuppressionThreshold
        ..min_pose_presence_confidence = options.minPosePresenceConfidence;
      final output = arena<mp.MpHolisticLandmarkerPtr>();
      checkVisionCreate(
        (error) => mp.MpHolisticLandmarkerCreate(native, output, error),
        gpu: _gpu,
      );
      _task = output.value;
    });
  }
  final bool _gpu;
  mp.MpHolisticLandmarkerPtr _task = nullptr;
  late final IosBgraStorage? _iosBgra =
      hasOfficialIosVisionRuntime() && iosImageStorageMode != 0
      ? IosBgraStorage(iosImageStorageMode)
      : null;
  @override
  HolisticLandmarkerResult process(VisionTaskInput input) => using((arena) {
    final (source, rotation, timestamp, _, _) = input;
    final image = createVisionImage(
      arena,
      source,
      expandRgbForGpu: _gpu,
      checked: checkVisionCall,
      iosBgra: _iosBgra,
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
    try {
      checkVisionCall((error) => mp.MpHolisticLandmarkerClose(task, error));
    } finally {
      _iosBgra?.close();
    }
  }
}
