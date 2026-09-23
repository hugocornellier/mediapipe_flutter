import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import '../../capabilities.dart';
import '../../third_party/mediapipe/vision_tasks_bindings.dart' as mp;
import '../../vision_task_backend.dart';
import '../sdk_vision_task.dart';
import '../capabilities/official_runtime_io.dart';
import 'native_ios_sdk.dart';
import 'native_vision_image.dart';
import 'native_vision_task.dart';
import 'vision_task_worker.dart';

/// Official GestureRecognizer, with owned results and serialized image/video inference.
///
/// On Android, a registered official SDK adapter
/// (`mediapipe_flutter_vision_android`) runs the task; elsewhere Google's
/// native runtime runs it on a worker isolate.
final class GestureRecognizer {
  GestureRecognizer._(this._worker, this._sdk, this.delegate);
  final VisionTaskWorker<GestureRecognizerResult>? _worker;
  final SdkVisionTask<GestureRecognizerResult>? _sdk;

  /// Requested backend, fixed until disposal.
  final VisionDelegate delegate;

  /// Mode selected when creating this task.
  VisionRunningMode get runningMode =>
      _sdk?.runningMode ?? _worker!.runningMode;

  /// Load a compatible task bundle on a worker isolate.
  static Future<GestureRecognizer> create(
    GestureRecognizerOptions options,
  ) async {
    if (Platform.isAndroid && gestureRecognizerBackendFactory != null) {
      return GestureRecognizer._(
        null,
        SdkVisionTask(
          await gestureRecognizerBackendFactory!(options),
          options.runningMode,
          options.delegate,
          name: 'GestureRecognizer',
          // MediaPipe converts milliseconds to signed 64-bit microseconds.
          maxTimestamp: 0x7fffffffffffffff ~/ 1000,
        ),
        options.delegate,
      );
    }
    final capabilities = await queryGestureRecognizerCapabilities();
    if (!capabilities.supportedDelegates.contains(options.delegate)) {
      throw UnsupportedError(
        capabilities.unavailableReasons[options.delegate]!,
      );
    }
    return GestureRecognizer._(
      await VisionTaskWorker.create(
        options,
        _createNative,
        'MediaPipe GestureRecognizer',
      ),
      null,
      options.delegate,
    );
  }

  /// Process one still image with official rotation preprocessing.
  Future<GestureRecognizerResult> recognizeImage(
    VisionImage image, {
    int rotationDegrees = 0,
  }) =>
      _sdk?.detectImage(image, rotationDegrees: rotationDegrees) ??
      _worker!.processImage(image, rotationDegrees, null);

  /// Process a video frame with a strictly increasing millisecond timestamp.
  Future<GestureRecognizerResult> recognizeForVideo(
    VisionImage image, {
    required int timestampMilliseconds,
    int rotationDegrees = 0,
  }) =>
      _sdk?.detectForVideo(
        image,
        timestampMilliseconds: timestampMilliseconds,
        rotationDegrees: rotationDegrees,
      ) ??
      _worker!.processVideo(
        image,
        rotationDegrees,
        timestampMilliseconds,
        null,
      );

  /// Drain queued requests and release native resources exactly once.
  Future<void> dispose() => _sdk?.dispose() ?? _worker!.dispose();
}

NativeVisionTask<GestureRecognizerResult> _createNative(
  GestureRecognizerOptions options,
) => _NativeGestureRecognizer(options);

final class _NativeGestureRecognizer
    implements NativeVisionTask<GestureRecognizerResult> {
  _NativeGestureRecognizer(GestureRecognizerOptions options)
    : _gpu = options.delegate == VisionDelegate.gpu {
    using((arena) {
      final native = arena<mp.MpGestureRecognizerOptions>();
      setVisionBaseOptions(
        arena,
        native.ref.base_options,
        options,
        officialGpu: true,
      );
      native.ref.running_mode = nativeVisionRunningMode(options.runningMode);
      native.ref
        ..num_hands = options.numHands
        ..min_hand_detection_confidence = options.minHandDetectionConfidence
        ..min_hand_presence_confidence = options.minHandPresenceConfidence
        ..min_tracking_confidence = options.minTrackingConfidence;
      setVisionGestureClassifier(
        arena,
        native.ref.canned_gestures_classifier_options,
        options.cannedGesturesClassifierOptions,
      );
      setVisionGestureClassifier(
        arena,
        native.ref.custom_gestures_classifier_options,
        options.customGesturesClassifierOptions,
      );
      final output = arena<mp.MpGestureRecognizerPtr>();
      checkVisionCreate(
        (error) => mp.MpGestureRecognizerCreate(native, output, error),
        gpu: _gpu,
      );
      _task = output.value;
    });
  }
  final bool _gpu;
  mp.MpGestureRecognizerPtr _task = nullptr;
  late final IosBgraStorage? _iosBgra =
      hasOfficialIosVisionRuntime() && iosImageStorageMode != 0
      ? IosBgraStorage(iosImageStorageMode)
      : null;

  @override
  GestureRecognizerResult process(VisionTaskInput input) => using((arena) {
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
      final result = arena<mp.MpGestureRecognizerResult>();
      if (timestamp == null) {
        checkVisionCall(
          (error) => mp.MpGestureRecognizerRecognizeImage(
            _task,
            image,
            processing,
            result,
            error,
          ),
        );
      } else {
        checkVisionCall(
          (error) => mp.MpGestureRecognizerRecognizeForVideo(
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
        return GestureRecognizerResult(
          gestures: copyVisionCategories(
            result.ref.gestures,
            result.ref.gestures_count,
            // Canned and custom classifiers number their own labels, so the
            // merged index is meaningless. The official bindings report -1.
            index: -1,
          ),
          handedness: copyVisionCategories(
            result.ref.handedness,
            result.ref.handedness_count,
          ),
          handLandmarks: [
            for (var i = 0; i < result.ref.hand_landmarks_count; i++)
              copyVisionNormalizedLandmarks(result.ref.hand_landmarks[i]),
          ],
          handWorldLandmarks: [
            for (var i = 0; i < result.ref.hand_world_landmarks_count; i++)
              copyVisionWorldLandmarks(result.ref.hand_world_landmarks[i]),
          ],
          imageWidth: mp.MpImageGetWidth(image),
          imageHeight: mp.MpImageGetHeight(image),
          timestampMilliseconds: timestamp,
        );
      } finally {
        mp.MpGestureRecognizerCloseResult(result);
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
      checkVisionCall((error) => mp.MpGestureRecognizerClose(task, error));
    } finally {
      _iosBgra?.close();
    }
  }
}
