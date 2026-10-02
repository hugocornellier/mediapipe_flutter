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

/// Google's Gesture Recognizer on its worker isolate.
final class NativeGestureRecognizer
    implements NativeVisionTask<GestureRecognizerResult> {
  /// Creates the task with the requested delegate and mode.
  NativeGestureRecognizer(GestureRecognizerOptions options)
    : _gpu = options.delegate == Delegate.gpu {
    using((arena) {
      final native = arena<mp.MpGestureRecognizerOptions>();
      setVisionBaseOptions(
        arena,
        native.ref.base_options,
        options,
        officialGpu: true,
      );
      native.ref.running_mode = nativeRunningMode(options.runningMode);
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
