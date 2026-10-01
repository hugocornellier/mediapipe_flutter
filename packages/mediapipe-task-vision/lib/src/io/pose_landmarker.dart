import 'dart:ffi';
import 'dart:io';

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

/// Official PoseLandmarker, with owned results and serialized image/video inference.
///
/// On Android, a registered official SDK adapter
/// (`mediapipe_vision`) runs the task; elsewhere Google's
/// native runtime runs it on a worker isolate.
///
/// ```dart
/// final task = await PoseLandmarker.create(
///   PoseLandmarkerOptions(model: VisionModels.poseLandmarker),
/// );
/// final image = VisionImage.fromFile('photo.jpg');
/// final result = await task.detectImage(image);
/// await task.dispose();
/// ```
/// Inference futures cannot cancel native work; `Future.timeout` only limits
/// caller waiting. `dispose()` drains accepted work and is idempotent.
final class PoseLandmarker {
  PoseLandmarker._(this._task, this.delegate);
  final VisionTaskRunner<PoseLandmarkerResult> _task;

  /// Requested backend, fixed until disposal.
  final VisionDelegate delegate;

  /// Mode selected when creating this task.
  RunningMode get runningMode => _task.runningMode;

  /// Load a compatible task bundle on a worker isolate.
  static Future<PoseLandmarker> create(
    PoseLandmarkerOptions options,
  ) async => PoseLandmarker._(
    await VisionTaskRunner.open(
      options,
      name: 'PoseLandmarker',
      debugName: 'MediaPipe PoseLandmarker',
      android: poseLandmarkerBackendFactory,
      capabilities: queryPoseLandmarkerCapabilities,
      validate: () {
        if ((Platform.isMacOS || Platform.isLinux) &&
            options.delegate == VisionDelegate.gpu &&
            options.outputSegmentationMasks) {
          // Metal fails on the first frame; OpenGL ES returns 8-bit RGBA images
          // where the API promises float confidences.
          throw UnsupportedError(
            Platform.isMacOS
                ? 'Google\'s macOS runtime cannot initialize the pose '
                      'segmentation mask upsampler on Metal (upstream-issues.md '
                      'UP-028). Request masks on the CPU, or landmarks alone on '
                      'the GPU.'
                : 'Google\'s Linux runtime returns pose masks on OpenGL ES as '
                      '8-bit RGBA images, not float confidences (upstream-issues.md '
                      'UP-030). Request masks on the CPU, or landmarks alone on the '
                      'GPU.',
          );
        }
      },
      native: _createNative,
    ),
    options.delegate,
  );

  /// Process one still image with official rotation preprocessing.
  Future<PoseLandmarkerResult> detectImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) => _task.image(image, rotationDegrees);

  /// Process a video frame with a strictly increasing millisecond timestamp.
  Future<PoseLandmarkerResult> detectForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) => _task.video(image, rotationDegrees, timestampMilliseconds);

  /// Drain queued requests and release native resources exactly once.
  Future<void> dispose() => _task.dispose();
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
    final (source, rotation, timestamp, _, _) = input;
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
